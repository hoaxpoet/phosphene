# Aurora Veil — Desk Research Findings (2026-05-18)

Pre-implementation prior-art audit. Three parallel research sweeps:

1. **Technical shader research** — Shadertoy / GitHub / WebGL aurora implementations + their algorithms.
2. **Music-visualizer + screensaver research** — Milkdrop / projectM / Magnetosphere / teamLab / Sigur Rós etc.
3. **Visual-signature + failure-mode research** — NASA/NOAA aurora physics + stylized-aurora failure-mode taxonomy.

This document is the durable artifact that drove the 2026-05-18 amendment to `AURORA_VEIL_DESIGN.md` §5. It is referenced from that amendment and from `prompts/AV.1-prompt.md`. Future preset-author sessions for Aurora Veil (AV.1 → AV.2 → AV.3) read this doc end-to-end before authoring; the prompt does not duplicate its content.

**Headline finding.** The original AV design (2D pixel shader with horizontal-proximity-to-centre-line ribbon construction) is architecturally distinct from every photographically-credible procedural aurora in the wild. The convergent prior-art recipe is **volumetric raymarch up a vertical column with domain-warped triangular noise + running-average smear + per-march-step palette cycling** (nimitz "Auroras," Shadertoy 2017), grounded in the **Lawlor-Genetti factorization** (2D electron-flux map × 1D height-dependent emission curve, WSCG 2011). The amendment pivots §5 to that recipe.

---

## Part 1 — Authoritative procedural-aurora recipes

### 1.1 nimitz "Auroras" (the canonical procedural recipe)

**Source.** [Shadertoy XtGGRt](https://www.shadertoy.com/view/XtGGRt) — nimitz, October 2017. The single most-forked procedural aurora shader on Shadertoy. Cited in every subsequent aurora implementation I found (Godot Shaders, Aurora Terrestris, Volumetric Aurora with Polar Reflection, Toni Sagrista's Gaia Sky port).

**Visual signature read.** Photographic-leaning. Green-base / magenta-crown stratification. Biological asymmetry. Slow motion. Multi-ribbon depth emerges from a single noise field traversed at varying altitudes. The clearest existence proof that procedural aurora *can* read as photographic in a real-time fragment-shader budget.

**Algorithm summary (reconstructed; live Shadertoy source CC-BY-NC-SA, see §4 below).**

1. **Triangular noise primitive `tri(x) = clamp(abs(fract(x) - 0.5), 0.01, 0.49)`.** Triangle waveform — sharp ribbon edges that smoothed Perlin can't produce. The 0.01 floor prevents division-by-zero in the final `1.0 / pow(rz * 29.0, 1.3)` clamp.
2. **2D triangle noise `tri2(p) = vec2(tri(p.x) + tri(p.y), tri(p.y + tri(p.x)))`.** Two-component output for domain warping.
3. **`triNoise2d` — five iterations of domain-warped triangular noise.** Initial `z=1.8, z2=2.5`; each iteration computes `dg = tri2(bp * 1.85) * 0.75`, rotates by `time * spd` (where `spd ≈ 0.06`), perturbs `p -= dg / z2`, multiplies `bp` by 1.3, decays `z` by 0.42 and `z2` by 0.45, rotates the position by `mm2(-time * 0.5)`. Returns `clamp(1.0 / pow(rz * 29.0, 1.3), 0, 0.55)`. **This is the load-bearing ribbon-shape function.** The recursive rotation per octave is what produces biological asymmetry no Perlin/Worley combination matches at the same cost.
4. **50-step volumetric raymarch up a vertical column.** Step distance grows polynomially: `pt = (0.8 + pow(i, 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4)`. Cheaper at the bottom of the column (dense detail near the curtain base) and coarser at the top (where the diffuse red crown lives).
5. **Per-step density × per-step palette.** At each step `i`, sample `rzt = triNoise2d(bpos.zx, 0.06)`; compute `col2.rgb = (sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043) * 0.5 + 0.5) * rzt`. **The `sin(...)` is an IQ-cosine palette evaluated by march-step `i`, which is the Lawlor-Genetti 1D height curve smuggled into the march loop.** Green-base / magenta-crown stratification emerges *by altitude*, not *by uv.y* — physically correct.
6. **Running-average smear `avgCol = mix(avgCol, col2, 0.5)`.** **The single line that converts noise into ribbon.** Without it, the column reads as volumetric salt-and-pepper. With it, samples at adjacent altitudes blur vertically into coherent vertical streaks. This is the trick most stylized aurora shaders miss.
7. **Exponential decay accumulator `col += avgCol * exp2(-i * 0.065 - 2.5) * smoothstep(0, 5, i)`.** Early steps near the bottom contribute most; smoothstep avoids hard cutoff at the camera plane.
8. **Final scaling.** `col *= clamp(rd.y * 15.0 + 0.4, 0, 1)` fades aurora below the horizon; `col * 1.8` final gain.

**Why all four load-bearing elements matter (this is the load-bearing distinction).**

- **(a) Triangular noise — not Perlin, not fBM-of-Perlin.** Replaceable only at the cost of losing the sharp ribbon edges. Even multi-octave fBM-Perlin gives Gaussian-blurred ribbons that read as fog. If we substitute the engine's `fbm8` for `triNoise2d` we lose the defining aurora-vs-fog signal.
- **(b) Recursive domain warp with per-octave rotation.** Without it, the noise field is statistically uniform across the frame and ribbons read as a repeating pattern.
- **(c) Per-march-step palette cycle (Lawlor height curve).** This is the only way to get green-base / magenta-crown stratification *physically* (by altitude) rather than *stylistically* (by uv.y or hand-painted gradient). The stylistic approach to stratification produces the failure-mode #10 "red below green" inversion when the ribbon curves; the Lawlor approach is invariant to curtain orientation.
- **(d) Running-average vertical smear.** Cheap but transformative. Adopt verbatim.

**Adoption strategy.** Clean-room reimplement the algorithm in Metal MSL from the description above + Roy Theunissen's published breakdown. The technique is not copyrightable; only the specific GLSL source is. ~30 lines of MSL. Cite nimitz + Lawlor in the shader header as algorithmic prior art.

### 1.2 Lawlor & Genetti, *Interactive Volume Rendering Aurora on the GPU* (WSCG 2011)

**Source.** [Paper PDF](https://www.cs.uaf.edu/~olawlor/papers/2010/aurora/lawlor_aurora_2010.pdf) — Orion Lawlor + Jon Genetti, University of Alaska Fairbanks, 2010 manuscript / WSCG 2011 publication. [Unity implementation on GitHub](https://github.com/olawlor/AuroraRendererUnity). [WebGL demo](http://lawlor.cs.uaf.edu/~olawlor/2019/AuroraRendererWebGL/).

**The physical anchor.** Models aurora as **emission = `H(z) × F(x, y)`** where `H(z)` is the height-dependent oxygen/nitrogen emission profile (peak green ~110 km, magenta-red ~200+ km, ground ~100 km cutoff) and `F(x, y)` is the 2D electron-flux footprint (noise-driven texture of where the auroral oval is bright at a given moment). Plus an analytic integrable atmosphere density approximation for the column integral.

**Why every photographically-credible aurora secretly does this.** nimitz's per-march-step `sin(1.0 - vec3(...) + i * 0.043)` IS the Lawlor `H(z)` curve. The `triNoise2d` IS the Lawlor `F(x, y)` (animated). The factorization is the underlying physics; the procedural recipe is a cheap evaluation of it.

**Operational consequence.** **Resist any temptation to put altitude into the noise call.** Altitude lives in the colour transform (palette indexed by march-step / world-y), the noise field is 2D (xz plane), and the column integral combines them. Designs that fold altitude into a 3D noise sample (`fbm(float3(x, y, z))`) produce monotonic top-to-bottom gradients (blue→green→pink wash) instead of the non-monotonic stratified bands real aurora has.

### 1.3 NeverSeenTheSky / Steven Wittens (the motion reference)

**Source.** [GitHub](https://github.com/unconed/NeverSeenTheSky), [shader source](https://github.com/unconed/NeverSeenTheSky/blob/master/shaders/aurora.glsl.html), [JSConfUS 2013 talk](https://www.youtube.com/watch?v=GNO_CYUjMK8).

**Why this matters.** The one public example where the **motion** of aurora is right, not just the shape. 2D MacCormack-advection fluid solver on a 256² grid drives a noise-driven density field; result watched in real time *moves like real aurora* — curling vortical flow of charged plasma, not the noise-pan motion of Shadertoy auroras.

**What we can borrow without paying the fluid-solver cost.**

- **Curl-noise on the advection vector field** instead of straight time-panning the noise sample coordinate. `triNoise2d(p + curl_noise(p, time * 0.1).xy * k)` gives vortical evolution at a fraction of the cost. Phosphene's V.1 noise tree already has `curl_noise`.
- **Two ribbons drifting at slightly non-parallel velocities.** Mimics the multi-ribbon parallax of NeverSeenTheSky's volume integration without rendering a true second column.
- **Radial pre-blur from camera direction.** Wittens' core optimisation — compresses depth complexity by smearing the volume along perspective. Probably not worth implementing for AV (Phosphene's fragment budget is tight enough already), but flag it for AV.3 polish if motion still feels "snappy" after the other fixes.

### 1.4 Roy Theunissen breakdown (the cheap baseline)

**Source.** [Blog breakdown](https://blog.roytheunissen.com/2022/09/17/aurora-borealis-a-breakdown/) + [Unity source](https://github.com/RoyTheunissen/Aurora-Borealis-Unity).

**Technique.** "Difference of two Perlin layers, take `abs()`" — produces thin-ridge structures that read as ribbon edges. Cheaper than triNoise2d's five-octave domain warp but produces stylized vertical "pipes" with uniform cross-section.

**Use as fallback only.** If AV.1's triNoise2d clean-room reimplementation underperforms its budget, the abs-of-difference fallback is the cheaper alternative — but it caps visual fidelity at "stylized aurora," not "photographic aurora." Document this as the perf-fallback path; don't adopt unless forced.

### 1.5 Magnetosphere precedent (the audio coupling reference)

**Source.** Robert Hodgin / Barbarian Group's iTunes 8 visualizer (2007–2008). [Project page](https://roberthodgin.com/project/magnetosphere). [CDM writeup](https://cdm.link/2008/09/flight404s-magnetosphere-the-new-visualizer-in-itunes-8/).

**Why relevant.** Not aurora-themed, but the closest mainstream music visualizer in spirit — luminous bands of moving light driven by per-particle attendance to specific FFT frequency bands. The visual reading is "aurora-adjacent."

**Audio-coupling lesson.** Continuous spectral coupling (one band → one population) is the proven idiom. Beat onsets are *not* the primary driver. The Phosphene audio routing (vocals_pitch → hue, sustained bass → brightness, drums → lateral kink) is a stem-aware refinement of the same architecture.

### 1.6 Sigur Rós tour visuals (the aspirational ambient model)

**Source.** [Behance gallery](https://www.behance.net/gallery/21495473/Sigur-Ros-Tour-Visuals-Screen-Content).

**Why relevant.** Closest professional reference for "ambient, slow, photographic, palette-synced-to-song-arc" visual identity. **Palette transitions on song-section boundaries, not on beats.** Build-ups produce visual brightness ramps; drops produce stillness. Beat-onset coupling is absent — the visuals breathe with the song.

**Operational consequence for Aurora Veil.** If `drums_energy_dev` → curtain kink fires on every beat, the preset becomes EDM-festival and abandons the Sigur Rós register. The drum-kink **must** be rare-event gated (high-amplitude drum-energy-dev only, with damped 1–2 s response) so the visual reads as occasional shudder, not per-beat pulse.

---

## Part 2 — Visual signature & failure-mode taxonomy

### 2.1 Photographic aurora — load-bearing visual signature

Sourced from NASA, NOAA, Canadian Space Agency, atmospheric-physics literature, and aurora photographer guides (citations in §4).

**Colour stratification by altitude (the most-violated rule).**

| Altitude | Emission | Colour | Notes |
|---|---|---|---|
| < 100 km | N₂ molecular (rare) | Pink/dark-red fringe | Visible only on the **bottom edge** of the brightest, most energetic curtains during strong storms |
| 100–150 km | O atomic (557.7 nm) | Green | The dominant band. Body of nearly every aurora photo. |
| 120–200 km | N₂⁺ ionic (rare) | Blue/purple | Narrow band; rarely visible to naked eye |
| 300–400+ km | O atomic ¹D state (long-lifetime) | Red crown | Only at very high altitude where collisional quenching is rare. **ALWAYS sits above green, never beside, never below.** |
| > 600 km | — | (atmosphere too diffuse to emit) | |

**Operational consequence.** Colour gradient runs **vertically and only vertically**. Green at the body, magenta sometimes at the bottom edge during high activity, red at the crown only at very high altitudes. Horizontal rainbow gradients across a curtain are physically impossible. Phosphene's IQ-palette evaluation by march-step (= world-y) is correct; evaluating by uv.x or by per-frame phase is wrong.

**Shape characteristics (Störmer 1955 taxonomy).** Arc → band → curtain/drapery → corona → rays/pillars → diffuse patch → pulsating patch. The defining dimensional fact: **aurora is a thin sheet seen edge-on** — ~10s of km front-to-back but hundreds of km tall. Edges read crisp from the side; diffuse from below.

**Temporal characteristics (multi-timescale, this is non-negotiable).**

| Timescale | What moves | Note |
|---|---|---|
| Minutes | Substorm advance: hemisphere brightens over ~5–10 min | Substorm onset is rare; not every track |
| Tens of seconds | Substrate drift; gentle curtain undulation | The "ambient" timescale |
| 2–20 seconds | Whole-curtain brightness pulsation (pulsating patches form) | Slow, soft |
| 0.1–0.2 s (5–10 Hz) | Ray brightness flicker within bright pillars | Fast but localised to active rays |
| < 0.02 s (50–80 Hz) | Sub-flicker on the brightest filaments only | Edge case |

**Continuous "ribbon flow" at a single speed is the music-viz failure mode.** Real aurora's dominant mode is "mostly stationary, occasional bursts." The substrate is mostly still; the dramatic stuff is fast-but-rare. Phosphene's mv_warp at `decay = 0.945` handles the substrate timescale; we need additional mechanisms for the sub-second ray flicker and the multi-second pulsation.

**Fine structure — vertical rays.** Spacing ~100 m (filament limit) to several km in coarser bundles. **Sharp edges, not Gaussian-blurred.** ≥ 4 octaves of noise needed to capture the multi-scale structure. Phosphene's V.1 noise tree provides `fbm4` and `fbm8`.

**Sky context.** Dark sky required for visibility (Kp ≥ 3 in dark-sky locations). **Aurora is emissive, not opaque — stars punch through bright aurora regions.** Compositing rule is **additive emission over the sky**, not alpha-blend. Foreground is silhouette (black or near-black mountain/forest/lake), aurora is the only chromatic emission in frame.

### 2.2 Failure-mode taxonomy (15 modes)

A render that exhibits any of these reads as "stylized" rather than photographic. The numbered modes are the actionable anti-pattern list — the AV.1 prompt should explicitly check each, and the implementation should be designed to avoid each by construction.

| # | Mode | Symptom | Root cause | What avoids it |
|---|---|---|---|---|
| 1 | **Rainbow horizontal-gradient ribbon** | Ribbon grades red→orange→yellow→green→blue→violet left-to-right like a Pride flag | `palette(uv.x)` indexed by horizontal coord for "colorful" effect | Lawlor height-curve indexed by world-y / march-step |
| 2 | **EDM neon ribbon (uniform saturation edge-to-edge)** | Thick #00FF00 / #FF00FF ribbons at full luminance, often with bloom + chromatic aberration | No brightness gradient inside the curtain; clamped `saturate(fbm * intensity)` cranked | Per-march-step density × exponential decay accumulator |
| 3 | **Horizontal wave bands, no vertical extent** | Flat horizontal undulating bands like water-surface waves | `sin(uv.x * k + time)` perturbing a horizontal line, no vertical structure function | Volumetric vertical-column raymarch |
| 4 | **Constant-speed flowing motion** | Entire aurora translates smoothly L→R at one speed, like a scrolling banner | `time` added directly to a coordinate that samples the noise field; no multi-timescale separation | mv_warp substrate drift + sub-second ray flicker noise + rare drum-onset accent |
| 5 | **Aurora-as-opaque-cloud (no stars through it)** | Stars stop at the aurora edge | `mix(sky, aurora, mask)` instead of `sky + aurora` | Additive compositing |
| 6 | **AI-hyper-saturation (Midjourney style)** | Every colour at full saturation everywhere; foreground over-painted with reflected aurora light | Diffusion-model training bias toward Instagram-aesthetic auroras | Restrained palette — green dominant, magenta/blue accents only |
| 7 | **Cyan-magenta-only "synthwave aurora"** | Entirely cyan and magenta, no green at all | Designer chose a brand palette before reading aurora physics | Green-dominant IQ-cosine palette anchor (peak green near low-y / mid march-step) |
| 8 | **Single-octave noise (pillow fBM)** | Soft, blurry, pillowy colour gradient with no internal structure | One-octave noise instead of multi-octave domain-warped | ≥ 4 octaves; triangular noise (not Perlin) for ribbon edges |
| 9 | **Symmetric / centered composition** | Aurora dead-center in frame as mirrored arch | Author centered the effect because it's easier | Off-axis centre-line drift; biased toward thirds |
| 10 | **Red below green (inverted stratification)** | Curtain with red at the bottom edge, green above | Author swapped gradient direction or used a sunset palette indexed bottom-to-top | Lawlor height-curve indexed by altitude, physically correct by construction |
| 11 | **Festival-strobe high-frequency flashing** | Entire aurora blinks on/off at 4–10 Hz or pulses per beat | Audio amplitude → whole-aurora luminance | Beat onset as rare accent with 1–2 s damped response; never primary driver |
| 12 | **Aurora over a daytime/bright sky** | Rendered against blue daytime / sunset / twilight | "Skybox always visible" without dark-sky gating | Dark night-sky context mandatory; foreground silhouette |
| 13 | **Hard-edged top AND bottom** | Sharp clean upper AND lower edges, like a painted band | Symmetric `smoothstep(lower, upper, y)` both edges same width | Sharp lower altitude cutoff, soft diffuse upper boundary (asymmetric) |
| 14 | **Beam reflections / hard "lasers"** | Discrete colored beams angled from a sky point toward the ground, visible cones | Confusion with god-ray rendering or "point light + directional cone" import | Rays follow vertical (magnetic field-line) only; no convergence to a focal point |
| 15 | **Foreground over-illuminated by aurora ground-bounce** | Landscape bathed in green light at moonlight-brightness | Aurora treated as point/area light source for Cook-Torrance pipeline | Foreground is silhouette; aurora's surface brightness is far too low to meaningfully illuminate ground |

**Phosphene-specific failure modes worth flagging on top of the 15:**

- **Beat-coupled saturation** (catalog Failed Approach #4): `saturation = base + bass_dev * k` reads as festival-flashing.
- **Free-running `sin(time)`** (Failed Approach #33): primary motion via `sin(time * k)` cycles at a fixed rate regardless of music; feels mechanical. Aurora's fold modulation must be `fbm`-driven, mv_warp-accumulated, or audio-anchored — not raw `sin(time)`.
- **One audio primitive driving two visual layers at the same timescale** (Failed Approach #67): if `bass_att_rel` drives both ribbon brightness *and* vertical-ray phase advance, the music reads twice through the same channel — "competing rhythms." Each visual layer consumes one primitive at one timescale.

### 2.3 The 9-question authenticity rubric

If the rendered output answers **YES to all of these**, it reads as authentic aurora. **NO to any** flags a specific failure mode above. Use as the AV.3 M7 acceptance gate.

1. **Vertical stratification only?** Colour gradient runs top-to-bottom (green body, red crown only at high altitude, pink fringe only at lower edge during high activity). No horizontal rainbow gradients. *(fails → #1, #10)*
2. **Green-dominant palette?** Green is the substrate; red/magenta/blue are *accents* on top of it, not equal-share competitors. *(fails → #6, #7)*
3. **Vertical ray fine structure?** Visible striations or pillars run perpendicular to the curtain band, sharper than the overall envelope, ≥ 4 octaves of noise so detail exists at multiple scales. *(fails → #8)*
4. **Multi-timescale motion?** Substrate drifts on tens-of-seconds; ray brightness flickers sub-second; whole-sky pulses on 2–20 s; substorm advances over minutes. No single uniform-speed translation. *(fails → #4, #11)*
5. **Emissive compositing, not alpha-blend?** Stars and faint sky structure visible *through* the aurora; sum-blend over dark sky, not opaque overlay. *(fails → #5)*
6. **Soft top, sharp bottom?** The lower edge has a recognizable boundary; the upper edge dissolves into space. *(fails → #13)*
7. **Off-axis composition with dark foreground context?** The aurora occupies a portion of the sky against a near-black surrounding and a silhouette foreground — not center-frame, not against a coloured sky. *(fails → #9, #12)*
8. **Brightness gradient within the curtain?** Internal regions vary from bright (active rays) to dim (diffuse glow); not uniformly saturated edge-to-edge. *(fails → #2)*
9. **No theatrical "beam" or ground-illumination cues?** No converging cones from a sky point; the foreground is silhouette, not aurora-lit. *(fails → #14, #15)*

---

## Part 3 — Audio-coupling lessons

### 3.1 What works (validated by Magnetosphere + projectM + TouchDesigner aurorae)

- **Continuous spectral coupling to slow-changing visual parameters.** Sustained bass → ribbon brightness. Matches Phosphene Audio Data Hierarchy Layer 1 (continuous energy bands primary).
- **High-information-rate continuous coupling to colour.** Vocals_pitch → ribbon hue is Sigur-Rós-grade IF smoothed. Pitch tracking on vocals is noisy; raw per-frame jitters. Use a 5-frame smoothing window or read smoothed-attack envelopes.
- **Beat onset as RARE accent, never primary.** Failed Approach #4 is the project's standing rule; Aurora Veil is the most exposed to violating it.

### 3.2 The drum-kink risk (highest in the original spec)

The original AV design routes `stems.drums_energy_dev` → mv_warp lateral UV displacement amplitude `0.003`. Per-beat firing → festival visual; the curtain kinks on every drum hit, breaking the "real aurora moves slowly" perceptual contract.

**Mitigation (mandatory).** Gate the kink on **a high-amplitude drum-energy-dev threshold (rare events only, not every beat)**, **with damped visual response** (a single drum hit produces a 1–2 second slow shudder, not a sharp instantaneous deflection). Operational form: maintain a `kinkAccumulator` driven by `drums_energy_dev * smoothstep(0.4, 0.7, drums_energy_dev)` (threshold ~0.5), decay at ~0.5 per second. The UV displacement reads `kinkAccumulator`, not the raw `drums_energy_dev`.

Verification: `AuroraVeilContinuousDominanceTest` (planned AV.2) asserts brightness-breathing amplitude exceeds kink amplitude by ≥ 10× under continuous-music input. The threshold + decay shapes the kink into a 10% event rather than a 100% event.

### 3.3 The vocals_pitch sourcing problem

**`SpectralHistoryBuffer` does NOT carry `vocalsPitchNorm`.** The original AV design references `SpectralHistoryBuffer[1920..2399]` for the pitch trail; that offset is actually `offsetBarPhase` (bar phase). There is no `offsetVocalsPitchNorm` in the buffer. The buffer holds: valence (0), arousal (480), beatPhase (960), bassDev (1440), barPhase (1920) — five 480-sample trails plus metadata, no vocal pitch.

**Resolution (AV.2 scope, deferred but recorded here).** Read `stems.vocals_pitch_hz` + `stems.vocals_pitch_confidence` directly from `StemFeatures` (MV-3c, floats 41-42). Normalize: `vocalsPitchNorm = clamp((log2(pitch_hz / 80) / 4), 0, 1)` (maps E2 ≈ 80 Hz → 0, C7 ≈ 2093 Hz → ~1). No history-trail visualization at AV.2; the mv_warp's temporal accumulation provides the implicit smoothing. If trail visualization is needed in a future increment, the right move is to **add `offsetVocalsPitchNorm` to `SpectralHistoryBuffer`** as an engine-level extension — but that's not AV.1 or AV.2 scope.

---

## Part 4 — Licensing & attribution

**nimitz Shadertoy "Auroras" license.** Shadertoy default license is CC-BY-NC-SA, incompatible with Phosphene's MIT license. Verbatim adoption of the source GLSL is therefore not permitted. **Algorithms are not copyrightable; only specific code expressions are.** Phosphene's adoption strategy is **clean-room reimplementation** of the algorithm in Metal MSL from the published descriptions (this document + Roy Theunissen's blog breakdown + Toni Sagristà's Gaia Sky writeup). The shader header cites nimitz + Lawlor-Genetti as algorithmic prior art:

```
// AuroraVeil.metal — clean-room MSL implementation of the procedural-aurora
// recipe described in:
//   - nimitz, "Auroras," Shadertoy XtGGRt (2017) — triangular-noise volumetric
//     raymarch + running-average smear + per-march-step palette cycling
//   - Lawlor & Genetti, "Interactive Volume Rendering Aurora on the GPU"
//     (WSCG 2011) — height-curve × 2D flux-map factorization
// The algorithm is reimplemented from published descriptions
// (docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md); no Shadertoy code is
// copied verbatim. CC-BY-NC-SA Shadertoy source IS NOT incorporated.
```

**Roy Theunissen breakdown** is published as a blog post (no explicit licence); algorithm descriptions are fair use. Cite as additional algorithmic source.

**Lawlor & Genetti paper** is publicly available academic work; technique adoption is standard practice. Cite formally in the shader header.

**Reference photography licensing.** The 5 reference images already curated in `docs/VISUAL_REFERENCES/aurora_veil/` carry an Unsplash-License-uncertainty caveat (one image is Getty-via-Unsplash partnership; standard Unsplash License may not apply). Resolution deferred to AV.3 reference re-curation if needed.

---

## Part 5 — Sources

### Procedural aurora shaders
- [Auroras — nimitz, Shadertoy XtGGRt](https://www.shadertoy.com/view/XtGGRt) — canonical recipe
- [Tri Noise 2D Heightmap — nimitz, Shadertoy wdl3Ds](https://www.shadertoy.com/view/wdl3Ds) — `triNoise2d` exposure
- [Aurora Borealis: A Breakdown — Roy Theunissen](https://blog.roytheunissen.com/2022/09/17/aurora-borealis-a-breakdown/) — algorithm walkthrough
- [Aurora-Borealis-Unity (Roy Theunissen, GitHub)](https://github.com/RoyTheunissen/Aurora-Borealis-Unity)
- [NeverSeenTheSky — Steven Wittens (GitHub)](https://github.com/unconed/NeverSeenTheSky) — motion reference
- [Making WebGL Dance — Wittens, JSConfUS 2013 (YouTube)](https://www.youtube.com/watch?v=GNO_CYUjMK8)
- [Volumetric Aurora Borealis with Polar Reflection — Godot Shaders](https://godotshaders.com/shader/volumetric-aurora-borealis-with-polar-reflection/)
- [Rendering volume aurorae and nebulae — Toni Sagristà (Gaia Sky)](https://tonisagrista.com/blog/2024/rendering-aurorae-nebulae/)
- [Aurora Sky — Shadertoy wfKyzt](https://www.shadertoy.com/view/wfKyzt) — failure-mode example
- [Aurora Borealis — mi_ku, Shadertoy ldfGWf](https://www.shadertoy.com/view/ldfGWf) — failure-mode example (festival neon)

### Physical / academic
- [Lawlor & Genetti — Interactive Volume Rendering Aurora on the GPU (PDF)](https://www.cs.uaf.edu/~olawlor/papers/2010/aurora/lawlor_aurora_2010.pdf)
- [AuroraRendererUnity (Lawlor, GitHub)](https://github.com/olawlor/AuroraRendererUnity)
- [Aurora Renderer WebGL demo (Lawlor)](http://lawlor.cs.uaf.edu/~olawlor/2019/AuroraRendererWebGL/)
- [AuroraSketcher (lun0522, GitHub)](https://github.com/lun0522/AuroraSketcher) — Lawlor port + spline-driven flux map

### Aurora physics & photography
- [NOAA SWPC Aurora Tutorial](https://www.swpc.noaa.gov/content/aurora-tutorial)
- [NASA — Guide to Finding and Photographing Auroras](https://science.nasa.gov/feature/nasas-feature/nasas-guide-to-finding-and-photographing-auroras/)
- [Canadian Space Agency — colours of the northern lights](https://www.asc-csa.gc.ca/eng/astronomy/northern-lights/colours-of-northern-lights.asp)
- [Space.com — Aurora colors explained](https://www.space.com/aurora-colors-explained)
- [EarthSky — Forms of aurora](https://earthsky.org/astronomy-essentials/forms-of-aurora-arcs-curtains-corona/)
- [Springer — Small-Scale Dynamic Aurora (review)](https://link.springer.com/article/10.1007/s11214-021-00796-w)
- [AGU/Wiley — Flickering aurora EMCCD imaging](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2010ja016333)
- [NASA THEMIS — auroras move to magnetic field rhythm](https://www.nasa.gov/feature/goddard/2016/nasa-s-themis-sees-auroras-move-to-the-rhythm-of-earth-s-magnetic-field)
- [PetaPixel — Truth and Lies of aurora photos](https://petapixel.com/2016/01/22/the-truth-and-lies-of-those-aurora-photos-you-see/)
- [Lights Over Lapland — what aurora looks like to the naked eye](https://lightsoverlapland.com/what-does-an-aurora-look-like-to-the-naked-eye/)
- [Lights Over Lapland aurora webcam](https://lightsoverlapland.com/aurora-webcam/) — real-time motion reference

### Music-viz & ambient-app precedents
- [Magnetosphere (Robert Hodgin / flight404)](https://roberthodgin.com/project/magnetosphere)
- [projectM Cream-of-the-Crop preset pack (GitHub)](https://github.com/projectM-visualizer/presets-cream-of-the-crop)
- [Sigur Rós Tour Visuals on Behance](https://www.behance.net/gallery/21495473/Sigur-Ros-Tour-Visuals-Screen-Content)
- [AuroraCalm (Google Play)](https://play.google.com/store/apps/details?id=com.forumsphere.auroracalm) — closest existing product

---

## Part 6 — Recommended implementation order

1. **AV.1 — Single-column raymarch foundation.** Sky + sparse stars + one column of triNoise2d-style raymarch + running-average smear + per-march-step palette cycle + mv_warp at conservative parameters. No audio reactivity. Silence-stable rendering. Verifies the procedural recipe works in our budget against the engine's V.1 utility tree.
2. **AV.2 — Second + third drift columns + audio routing.** Add the multi-ribbon parallax (two more drifting columns at slightly non-parallel velocities, depth-scale dimmed). Wire the six audio routes per AV_DESIGN §5.6 — but with the drum-kink rare-event gate + damped response from §3.2 above, and with vocals_pitch sourced from `stems.vocals_pitch_hz` per §3.3.
3. **AV.3 — Multi-timescale motion + refinement + cert.** Add the sub-second ray-flicker noise layer (5–10 Hz character) and the 2–20 s whole-curtain pulsation. Tune palette constants + mv_warp amplitudes against curated references. Matt M7 review against the 9-question authenticity rubric (§2.3); on green, flip `certified: true`.

The architectural pivot from the original design's 2D-pixel-ribbon to the volumetric-raymarch recipe is the single highest-leverage change. Subsequent tuning lands on a much firmer foundation.
