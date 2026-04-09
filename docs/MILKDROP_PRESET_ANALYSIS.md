# Milkdrop Preset Creative Vocabulary Analysis

Comprehensive analysis of the "Cream of the Crop" curated Milkdrop preset collection. This document catalogs the full creative vocabulary — spatial patterns, audio response techniques, shader tricks, and per-category design signatures — to inform Phosphene's shader and preset system design.

---

## Repository Structure Overview

11 top-level categories, ~150 subcategories, thousands of .milk preset files.

| Category | Subcategories | Approx. Total Presets | Key Character |
|----------|--------------|----------------------|---------------|
| Sparkle | 10 | ~800 | Bright particles, gem-like refraction, mass instanced shapes |
| Hypnotic | 8 | ~280 | Polar/bipolar transforms, optical illusions, Escher-like patterns |
| Geometric | 40 | ~900 | 3D wireframe objects, cubes, spheres, tunnels, stripes |
| Supernova | 7 | ~380 | Radiant central explosions, starfields, gas nebulae |
| Particles | 9 | ~390 | Point clouds, swarms, trails, orbiting dots |
| Dancer | 32 | ~1,300 | Articulated humanoid figures (glowstick dancers), mirror variants |
| Drawing | 21 | ~1,140 | Generative art, organic growth, liquid strokes, trails |
| Fractal | 26 | ~1,400 | Nested shapes, Sierpinski, Mandelbox, lattices, self-similarity |
| Reaction | 19 | ~1,790 | Reaction-diffusion, liquid simulation, cellular automata |
| Waveform | 10 | ~1,280 | Spectrum displays, spirograph waves, circular/flat waveforms |
| Transition | 1 (flat) | 4 | Crossfade/zoom-to-black transition presets |

---

## Milkdrop Architecture Primer (for Phosphene context)

A Milkdrop preset has these programmable layers, executed each frame:

1. **per_frame equations** — Set global uniforms (zoom, rot, decay, cx, cy, dx, dy, warp, sx, sy) and q-variables (q1-q32) for passing data to shaders. This is where audio response logic lives.

2. **per_pixel equations** — Run on a coarse grid (~32x24 to 64x48). Each grid vertex gets `x`, `y`, `rad`, `ang` and can modify `zoom`, `rot`, `dx`, `dy`, `warp`, `sx`, `sy`. The Milkdrop engine interpolates these across the mesh to create spatially-varying feedback transforms. This is the primary mechanism for tunnels, vortices, kaleidoscopes, etc.

3. **Warp shader** (HLSL, PSVERSION >= 2) — Replaces the built-in per-pixel mesh interpolation. Reads `sampler_main` (previous frame), `sampler_noise_*`, `sampler_noisevol_*`. Outputs `ret` (RGB). Has access to `uv` (warped), `uv_orig` (unwarped), `texsize`, `time`, `bass`/`mid`/`treb`/`*_att`, blur levels.

4. **Composite shader** (HLSL) — Post-processing pass. Reads the warped frame via `GetPixel(uv)`, blur levels via `GetBlur1/2/3(uv)`, plus all audio/time uniforms. Outputs final `ret`. This is where kaleidoscope effects, color grading, edge detection, and polar remapping typically live.

5. **Custom waves** (wavecode_0-3) — Up to 4 custom waveforms, each with per_frame and per_point code. 512 samples. Used for drawing 3D wireframe objects, spirographs, particle systems, articulated figures.

6. **Custom shapes** (shapecode_0-3) — Up to 4 custom shapes with `num_inst` instances (up to 1024). Each instance runs per_frame code to set x/y/rad/ang/color/alpha. Used for instanced particle systems, scattered dots, 3D projected geometry.

7. **Global megabuf** — Shared array (gmegabuf) for passing data between shapes, waves, and frames. Used for persistent particle positions.

---

## Category-by-Category Analysis

### 1. SPARKLE

**Subcategories**: Explosions (434), Jewel (48), Glimmer (29), Glimmer Mirror (54), Glimmer Tunnel (29), Mass Circles (99), Mass Squares (29), Mass Stars (46), Mass Triangles (14), Squares (15)

#### What Makes Sparkle Visually Distinct

Sparkle presets produce bright, gem-like, crystalline visuals. They rely heavily on composite shader tricks that re-read the feedback texture through radial/polar UV transforms, creating the appearance of light refracting through cut crystal or exploding from a central point. Dark backgrounds with intense bright points and facets.

#### Sparkle/Explosions

The largest single subcategory (434 presets). Key techniques from representative presets:

**Per-pixel spatial patterns**: `zoom = 1.0 + 0.05*sin(ang*12 - 10*sin(time*0.73) - rad*20*cos(time*0.31) - time*0.8)`. This creates a complex spatially-varying zoom that oscillates with angle (creating radial petals) and radius (creating concentric ripple effects). The rotation also varies: `rot = 0.21*sin(rad*10 - 0.1*cos(ang*6) + 1.21*time)`.

**Composite shader**: Converts to polar coordinates (`ang/3.14`, `0.1/rad`), applies time-based scrolling, reads the feedback texture through this polar mapping. This creates the classic "explosion" effect where the center appears to emit light outward. The `1/rad` term produces the inverse-radius tunnel/starburst mapping.

**Audio response**: Beat detection via `bass_att` threshold — when `bass_att` exceeds a decaying threshold, `dx_r` and `dy_r` get randomized. The `frac(ret - dec)` in the warp shader creates color-cycling by wrapping colors, with `dec` driven by `vol/vol_att`.

**Key warp technique**: Error diffusion dithering via noise texture sampling, plus `frac()` on the color output to create smooth color wrapping rather than hard clipping.

#### Sparkle/Jewel

Crystal palace presets with elaborate warp shaders that create faceted, gem-like geometry.

**Crystal faceting**: `sin(uv1 * mult)` creates a repeating grid of distorted cells, then `atan2` quantizes the angle with `floor()` to create hard-edged facets. Distance-based modulation (`1 - cos(8*dist)`) creates bright edges between facets.

**Background tunnel**: `clamp(tan(z) * normalize(uv1), -5, 5)` where z depends on `length(uv1) + time`. The `tan()` creates periodic singularities (bright rings) that scroll with time, producing a pulsing tunnel backdrop behind the crystal facets.

**Audio response**: Beat detection system using `avg * dec_slow + beat * (1 - dec_slow)` with index counting. Beats trigger state changes (rotation direction, crystal parameters). `q26 = max(atan(vol - v2*0.8), 0.3)` — a saturating volume metric drives brightness. Beats also rotate the crystal orientation in discrete pi/2 steps (smoothed via EMA).

**Composite shader**: Multiple rotated copies sampled with distance-based intensity falloff: `inten = 16*dist*(1-dist*dist)`. This creates the jewel facet multiplication effect.

#### Sparkle/Mass Stars

Uses noise-based tiling in the composite shader to scatter star-shaped bright points across the screen. `floor(uv * 10) * 0.1 + rand_preset` creates a grid, noise lookup determines which cells get stars, and color is derived from multiple `lerp()` calls against `GetPixel`, `GetBlur1`, `GetBlur2` at the noise-offset UVs. The warp shader adds high-frequency noise to UVs for sparkle shimmer.

---

### 2. HYPNOTIC

**Subcategories**: Illusion (17), Illusion Radiate (12), Polar Rolling (23), Polar Mirror (52), Polar Closeup (15), Polar Static (62), Polar Warp (95), Radial Warp (4)

#### What Makes Hypnotic Visually Distinct

These presets create mesmerizing, never-ending patterns through advanced UV remapping in shaders. The dominant technique is **polar/bipolar/Moebius transformation** of UV coordinates. Content appears to rotate, spiral, and tile infinitely. Strong mathematical foundation — Flexi's "Box of Tricks" library provides reusable complex math functions.

#### Hypnotic/Illusion

**Flexi's complex analysis toolkit**: The warp shader defines utility functions for:
- `complex_div()` — Complex number division
- `uv_moebius_transformation()` — Maps two points to 0 and infinity via Moebius transform
- `uv_polar()` — Cartesian to polar
- `uv_polar_logarithmic_inverse()` — Logarithmic spiral mapping with configurable "fins" (angular repetition count)
- `uv_bipolar_logarithmic_inverse()` — Combines Moebius + polar + logarithmic for bipolar coordinate systems
- `uv_lens_half_sphere()` — Physical lens refraction simulation (Snell's law)

A single preset chains these: lens distortion at center, then bipolar logarithmic mapping with 3 fins, creating an infinitely recursive Escher-like tiling where content spirals inward and tiles angularly simultaneously.

**Key insight for Phosphene**: These transforms create visual infinity from finite content. The UV transforms are purely geometric — they could be implemented as reusable Metal shader functions.

#### Hypnotic/Polar Rolling

**Reaction-diffusion + bipolar composite**: The warp shader implements a GPU-based reaction-diffusion system:
- Compute gradient of blur levels: `dx = GetBlur1(uv + d) - GetBlur1(uv - d)`
- Use gradient to advect the texture: `my_uv = uv + float2(dx,dy) * texsize.zw * motionStrength`
- Add diffusion noise and slow decay
- RGB channels advected independently by different gradient components

The composite shader then remaps through bipolar coordinates (3x nested): Moebius transform, polar logarithmic mapping, mirror folding via `0.5 - abs(frac(uv * 0.5) * 2.0 - 1.0)`. The nesting creates infinite depth.

**Audio response**: Predator-prey differential equations (Lotka-Volterra) drive the warp field! Bass/mid/treb are integrated and normalized, then the *differences* between normalized band energies drive accumulating bipolar coordinate offsets (`q10 = bm; q11 = mt; q12 = bt`). This means the bipolar mapping shifts based on which frequency bands are relatively dominant — a sophisticated spectral-to-visual mapping.

#### Hypnotic/Polar Warp

The largest Hypnotic subcategory (95 presets). Similar reaction-diffusion warp systems with various polar composite mappings. The per_pixel code applies predator-prey vector fields as dx/dy displacement. Per-pixel rotation is applied to the entire field to match the warp. The composite uses nested bipolar transforms with mirror folding.

**Key creative technique**: Gradient-based advection in the warp shader creates self-organizing patterns (similar to Gray-Scott reaction-diffusion), which are then viewed through the hypnotic polar kaleidoscope of the composite shader. The content self-generates, the view transforms.

---

### 3. GEOMETRIC

**Subcategories (40 total, notable ones)**: Wire Circles (103), Wire Morph (88), Wire Trace (73), Wire Grid (52), Wire Spiral (44), Tunnel Spheres (44), Sphere Wild (202), Sphere Particles (25), Cube (30), Cube Fly (21), Cube Array (14), Stripes (23), Stripes Circle (17), Cathedral (19), Honeycomb (16), Wire Flower (22), Wire Sphere (19), Wire Torus (18)

#### What Makes Geometric Visually Distinct

3D wireframe objects rendered in screen space via custom wave per_point equations. Each wave's 512 sample points define a 3D polyline that is rotated (using sin/cos matrix multiplication) and perspective-projected (`x = xp/zp + 0.5`). Multiple waves (up to 4) draw different faces of the same object. Textured shapes provide fill. The feedback loop (zoom/decay) creates trails behind moving geometry.

#### 3D Projection Pipeline (found in Cube, Sphere, Wire categories)

The standard 3D projection pattern used across hundreds of geometric presets:

```
// Define 3D point from sample parameter
xp = f(sample); yp = g(sample); zp = h(sample);

// X rotation
sang=sin(q1); cang=cos(q1);
xn=xp; yn=yp*sang+zp*cang; zn=yp*cang-zp*sang;
xp=xn; yp=yn; zp=zn;

// Y rotation (similar)
// Z rotation (similar)

// Perspective projection
zp = zp + camera_distance;
x = xp/zp + 0.5;
y = yp/zp * aspect_ratio + 0.5;
```

**Audio-driven rotation**: Rotation angles come from per_frame q-variables that accumulate audio-weighted time: `mtime = mtime + pow(mid,2) * 0.01; q2 = mtime * 0.5;`. The `pow(mid,2)` makes rotation speed proportional to mid-range energy squared, so loud passages spin faster.

**Audio-driven shape deformation (Cube example)**: `bend = (1 - pow(abs(sample*2-1), 2))` creates a bell curve along the edge. `xp = t8 * (1 - bend*0.7*t2)` where `t2 = sin(time*3.3)*0.5 + 0.5` — the cube faces flex inward/outward with a time-varying and audio-modulated deformation parameter.

#### Geometric/Wire Spiral

Spiral wave pattern by Stahlregen: `x = centerx + (size - size*sample) * sin(speed*3.14*time + sample*6.28*turns) * (1 + amplitude*(value1+value2))`. The spiral is defined parametrically where `sample` (0..1) controls both radius and angle simultaneously. Audio modulates the `amplitude` via `bass_att`, causing the spiral to breathe.

**Warp shader gradient advection**: Each RGB channel is advected independently by a different component of the blur gradient. `ret.x = GetPixel(uv_x).x` where `uv_x` is offset by the x-component of the blur gradient. Combined with `ret -= ret.yzx * 0.1 - 0.014`, this creates per-channel color separation that evolves into psychedelic rainbow trails.

**Composite shader edge detection**: `dx = GetPixel(uv + d) - GetPixel(uv - d)` computes a per-pixel gradient. `ret = GetPixel(uv).x * (1 - length(float2(dx.y, dy.y) * 8)) * pow(hue_shader, 6)` — the edge magnitude modulates brightness, while `hue_shader` (a built-in Milkdrop time-cycling hue) provides color.

#### Geometric/Stripes & Honeycomb

Use `frac()` and `floor()` to create repeating geometric tiles. The hex grid function from Flexi's toolkit: `bool hex(float2 domain)` tests if a point falls within a hexagonal cell using 8 half-plane intersection tests. Three-phase hexgrid coloring (`bool3`) enables different colors per hex tile.

#### Geometric/Tunnel Spheres

Same 3D projection pipeline but with sphere geometry (sin/cos of two angles). The `num_inst` shape system places textured circles at projected 3D positions, creating a cloud of spheres in perspective.

---

### 4. SUPERNOVA

**Subcategories**: Burst (131), Gas (31), Lasers (18), Orbits (26), Radiate (136), Shimmer (10), Stars (28)

#### What Makes Supernova Visually Distinct

Bright central sources radiating outward. Strong zoom-in feedback (zoom > 1.0) creates content that appears to explode from the center. High decay (0.95-0.985) preserves trails. Color cycling via wave_r/g/b time-modulation. The composite shader frequently uses angular kaleidoscoping ("fins") to create radial symmetry.

#### Supernova/Radiate

**Per-frame audio**: `zoom = zoom + 0.013 * (0.60*sin(0.339*time) + 0.40*sin(0.276*time))` — zoom oscillates slowly. `rot` oscillates similarly. Critical line: `zoom = zoom + (bass_att - 1) * 0.2` — bass energy drives zoom, creating audio-synchronized expansion pulses.

**Composite "fin" kaleidoscope**: The universal Supernova composite technique:
```
ang2 = ang_lq * M_INV_PI_2;    // normalize angle to 0..1
ang2 += time * 0.025;           // slow rotation
fins = 3 + floor(rand_preset.z * 5.95);  // 3-8 fins per preset
ang2 = frac(ang2 * fins) / fins;          // angular folding
ang2 = abs(ang2 - 0.5/fins);             // alternating mirror
uv2 = 0.5 + rad2 * float2(cos(ang2), sin(ang2)) * texsize.zw;
ret = tex2D(sampler_main, uv2);
```
This folds the angular coordinate so N identical wedges tile the circle. `abs()` creates mirror symmetry within each wedge. The content zooms outward due to per-frame zoom > 1, and the fin kaleidoscope multiplies it into a radial star pattern.

#### Supernova/Burst

Combines the fin kaleidoscope with cloud-based warp shaders. The warp shader in the studied preset generates procedural clouds via octave noise: `n1 = tex3D(noisevol_hq, float3(uv, z))` at 4 octaves with 1/f weighting. Clouds advect slowly and modulate the UV before the main texture sample. Audio drives a "sun" brightness: `(1+bass_att)*0.01/length(uv - sunpos)`.

Beat detection drives random shape placement: shapes appear at random positions on beats, with randomized radius and rotation. Multiple shape instances (33) with random colors fire simultaneously on beats.

#### Supernova/Stars

**3D starfield via custom waves**: 4 wave channels, each drawing 128 "star lines" at different radii (0.4, 0.4, 1.1, 1.6) and different angular distributions. Each star is a short line segment in 3D space with depth-dependent alpha (fading with distance). Full 3D rotation with forward movement driven by `q6` speed factor. Stars wrap around in depth for infinite scrolling.

**Audio response**: Mid energy squared accumulates into `mtime`, which drives Y-axis rotation. Treb energy squared drives additional rotation parameter. Volume drives gamma brightness — louder moments are brighter. The per-pixel code adds radial zoom variation: `zoom = 1 + sin(ang*9 + time)*0.03` creating a subtle angular breathing effect.

---

### 5. PARTICLES

**Subcategories**: Blobby (70), Crystal (20), Grid (31), Orbit (30), Points (75), Points Fast (17), Points Trails (90), Spaz (28), Swarm (28)

#### What Makes Particles Visually Distinct

Point-based systems — waveform dots (bUseDots=1) scattered by audio values, or shape instances with tiny radii. The feedback system creates trails. Unlike Geometric (which draws connected lines), Particles emphasizes disconnected points that swarm, orbit, or scatter.

#### Particles/Points Trails

**Motion blur warp shader** (by Geiss): The key technique that creates trails:
```
float2 v = normalize(uv - uv_orig) * texsize.zw;  // motion direction
ret = max(ret, tex2D(sampler_main, uv + v*-1) * 0.90);
ret = max(ret, tex2D(sampler_main, uv + v* 1) * 0.97);
ret = max(ret, tex2D(sampler_main, uv + v* 2) * 0.97);
ret = max(ret, tex2D(sampler_main, uv + v* 3) * 0.90);
ret *= 0.92;  // global decay
```
This samples the previous frame at offsets along the motion direction (computed from the difference between warped and original UVs), taking the `max()` of all samples. This creates bright directional trails behind moving points. The decay ramp (0.90, 0.97, 0.97, 0.90) creates a smooth falloff.

**Per-pixel radial zoom**: `zoom = zoom + rad * 0.1 * q1` where `q1 = 0.05 * pow(1 + 1.2*bass + 0.4*bass_att + ..., 6) / fps`. The 6th power creates highly nonlinear response — quiet passages have almost zero zoom, loud passages have enormous zoom. The `rad` multiplier means zoom increases with distance from center, creating a radial burst effect.

**Composite fin kaleidoscope**: Same angular folding as Supernova, with `cos(ang2 * M_PI_2 * fins) * 0.023` for soft cosine fins rather than sharp frac/abs fins.

#### Particles/Grid

Grid-based particle layouts — the per_pixel mesh itself becomes a visible grid of dots via motion vectors (`mv_a > 0`), or shape instances arranged in a grid pattern with noise displacement.

---

### 6. DANCER

**Subcategories (32)**: Glowsticks (152), Glowsticks Mirror (236), Comet Mirror (97), Blobby (74), Blobby Mirror (74), Whirl (64), Wake Mirror (53), Shapes (51), Lasers (104), others

#### What Makes Dancer Visually Distinct

The most technically impressive category. Custom wave per_point code implements **articulated 3D humanoid figures** using forward kinematics. Two arms, each with wrist, forearm, upper arm joints. Joint angles are driven by sinusoidal functions of audio-weighted time, creating dancing motion that responds to music.

#### Dancer/Glowsticks — The Articulated Figure System

**Forward kinematics chain** (per wave, per 512 sample points):

1. **Start at wrist**: `xp=0; yp=flip*0.1 + (sin(tm)*0.5+0.5)*0.2` — flip alternates between two edges of the hand/wrist
2. **Wrist rotation**: Rotate (xp,yp,zp) around X-axis by `sin(tm*2)*0.5+0.5`
3. **Wrist spin**: Rotate around Y-axis by `tm*8` (fast spinning = glowstick trail)
4. **Forearm**: Translate `zp -= 0.3`, rotate by `3.14 + sin(tm*2-0.5)*1.5` (elbow bend)
5. **Upper arm twist**: Rotate by `-1.0 + cos(tm*3.1+0.5)` (shoulder twist)
6. **Upper arm outward**: Translate `zp -= 0.35`, rotate by `cos(tm*2.3)*1.75 - 1.05` (arm raise)
7. **Upper arm up/down**: Final rotation by `cos(tm)*0.5 - 0.5`
8. **Perspective project**: `zp = zp + 2; x = xp/zp + 0.5; y = yp/zp * 1.3 + 0.5`

The `tm` variable is driven by audio: `mtime = mtime + vol*0.1` where `vol = (bass_att + mid_att + treb_att)*0.25; vol = vol*vol`. This creates music-synchronized dancing.

**Color**: Direction-based coloring via `cang = atan2(dx, dy)` of the segment direction. `r = 0.5 + 0.5*sin(cang)`, creating rainbow colors that follow the limb direction.

**Motion blur warp shader**: Same Geiss motion blur technique as Particles/Points Trails. Combined with high decay, this creates glowing trails behind the figure — hence "glowsticks".

4 waves = 4 limbs (two arms, mirrored). The Mirror variants add `x = -xs + 0.5` to double the figure.

---

### 7. DRAWING

**Subcategories (21)**: Explosions (304), Liquid (223), Trails (129), Trails Mirror (144), Liquid Mirror (108), Growth (79), others

#### What Makes Drawing Visually Distinct

Generative art that looks hand-drawn or painted. These presets draw colored paths on the screen using custom wave per_point code where a "brush" position is updated each sample-step based on audio-driven direction changes. The feedback loop preserves and transforms previous strokes.

**Key Drawing technique — the Random Walk Brush**:
```
ma = ma + (above(bass,1) * 3.1415 * 0.01 * bass);
ma = ma - (above(treb,1) * 3.1415 * 0.01 * treb);
mx = mx + (0.0002 * cos(ma));
my = my + (0.0002 * sin(ma));
// Boundary wrapping
mx = if(above(mx, 0.9), (0.9-mx), mx);
my = if(above(my, 0.9), (0.9-my), my);
x = mx; y = my;
```

Bass rotates the brush direction one way, treble the other. The brush walks slowly across the screen, changing direction based on which frequency band is dominant. This creates organic, audio-reactive drawings that build up over time.

---

### 8. FRACTAL

**Subcategories (26)**: Nested Circle (216), Nested Spiral (179), Nested Square (156), Lattice (143), Core (95), Core Mirror (60), Nested Dancer (70), Nested Ellipse (41), Core Tunnel (37), Mandelbox (34), Loops (30), Sierpinski (23), Nested Pyramid (21), Nested Spiral Multiple (19), others

#### What Makes Fractal Visually Distinct

Self-similar nested geometry. The dominant technique is using **textured shapes** that sample the feedback texture as their fill — creating recursive nesting where the entire scene appears inside each shape, at a smaller scale and rotated.

**The Nested Shape Technique**: A `shapecode` with `textured=1` and `tex_zoom < 1` (e.g., 0.6-0.9). The shape samples the feedback texture at a zoomed/rotated offset, so each shape contains a smaller version of the entire frame. Combined with the feedback loop (zoom slightly > or < 1.0), this creates infinite recursive nesting.

**Fractal/Sierpinski**: Flexi's cellular automata approach — Wolfram's Rule 90/110 implemented in per_pixel/warp shader code. Not traditional fractals but emergent fractal-like patterns from simple rules.

**Fractal/Mandelbox**: Uses the warp shader to implement distance-field marching or iterative fold operations characteristic of Mandelbox fractals.

**Fractal/Lattice**: Complex repeating grids using `frac()` and `floor()` to tile content, combined with rotations that vary with position to create Escher-style impossible lattices.

---

### 9. REACTION

**Subcategories (19)**: Liquid Ripples (470), Liquid Blobby (196), Rorschach (191), Liquid Gradient (123), Liquid Windy (125), Feedback (124), Liquid Simmering (111), Liquid Closeup (87), Growth (79), Contagion (46), Crystalize (40), Whirlpools (40), Dunes (35), Maze (27), Automata (26), others

#### What Makes Reaction Visually Distinct

The largest category overall. Self-organizing patterns that emerge from local interaction rules implemented in the warp shader. The content generates itself — audio modulates parameters of the self-generating system rather than directly drawing anything.

**Reaction-Diffusion in the Warp Shader**:
The standard technique, seen across Liquid Ripples and most Reaction subcategories:
```
float2 d = texsize.zw * pixelDistance;
float3 dx = GetBlur1(uv + float2(1,0)*d) - GetBlur1(uv - float2(1,0)*d);
float3 dy = GetBlur1(uv + float2(0,1)*d) - GetBlur1(uv - float2(0,1)*d);
float2 my_uv = uv + float2(dx.y, dy.y) * texsize.zw * motionStrength;
ret.y = tex2D(sampler_main, my_uv).y;
ret.y += (ret.y - b1.y) * 0.02 + decay;
```

Per-channel advection (each RGB channel follows a different gradient component) creates self-organizing multi-colored patterns. The blur-based gradient computation creates multi-scale interactions — nearby pixels influence each other, creating fluid-like behavior.

**Curl noise variant** (Reaction/Liquid Windy): Instead of gradient advection, uses `float2(dy.x, -dx.x)` (curl of the gradient) for rotational flow patterns.

**Reaction/Rorschach**: Same reaction-diffusion with `sx = -1` (horizontal mirror) to create bilateral symmetry, producing Rorschach inkblot patterns.

**Audio response**: Audio typically modulates the reaction rate (`c = 0.005` growth constant), the decay rate, or injects energy via the custom wave brush positions. The system self-organizes regardless; audio just nudges parameters.

---

### 10. WAVEFORM

**Subcategories (10)**: Wire Tangle (268), Spectrum (258), Wire Circular (183), Wire Spirograph (150), Wire Flat (112), Wire Flat Double (99), Wire Mirror (73), Wire Rising (52), Wire Tunnel (53), Wire Flower (31)

#### What Makes Waveform Visually Distinct

Direct visualization of audio data. Unlike other categories that use audio to modulate abstract visuals, Waveform presets make the audio waveform or spectrum visible as geometric patterns.

**Wire Spirograph**: `x = 0.5 + (bass*0.2) * sin(sample*2 * (time*10*treb))` and `y = 0.5 + (bass*0.2) * cos(...)`. The radius is `bass*0.2` (audio-amplitude-modulated), the angular frequency is `time*10*treb` (treble-modulated speed), and `sample` sweeps the angle. This traces a Lissajous/spirograph pattern whose size pulses with bass and whose complexity varies with treble. RGB color varies per-sample with different audio band modulations.

**Wire Circular**: Polar plot of waveform — `x = 0.5 + (0.3 + value1*amplitude) * cos(sample*2*pi)`. The raw audio sample value modulates the radius.

**Spectrum**: Uses `bSpectrum=1` to display frequency magnitudes instead of time-domain waveform.

---

### 11. TRANSITION

**Subcategories**: 1 flat directory with 4 presets

Utility presets for smooth transitions between other presets. Techniques:
- **Radial blur to black**: `ret = (tex2D(v*-4.5)*0.19 + tex2D(v*-1.5)*0.31 + tex2D(v*1.5)*0.31 + tex2D(v*4.5)*0.19) - 0.009`. Gaussian radial blur samples along the direction from center, each frame subtracting a small constant. Progressive blur + darken = smooth fade to black.
- **Gas effect**: Noise-based UV displacement before sampling, creating a dissolving effect.
- Controlled zoom in or out during the transition.
- Gamma boost for visible mid-transition.

---

## Creative Techniques Beyond Simple Zoom+Rotation

### 1. Per-Channel Gradient Advection
Each RGB channel is transported by a different component of the image gradient. Creates self-organizing, multi-colored reaction-diffusion patterns. Found in Reaction, Hypnotic, and some Geometric presets.

### 2. Polar/Bipolar/Moebius UV Remapping
Complex conformal mappings in the composite shader create infinite-depth patterns from finite feedback content. Key transforms: Moebius (maps two points to 0/infinity), polar-logarithmic (spiral tiling), bipolar (two-center polar). Found primarily in Hypnotic.

### 3. Angular Kaleidoscope ("Fin" Effect)
`ang2 = frac(ang * fins) / fins` creates N-fold angular symmetry. `abs(ang2 - 0.5/fins)` adds mirror folding within each wedge. Universal across Supernova, Sparkle, and some Particles.

### 4. Motion Blur via Directional Max-Sampling
`ret = max(ret, tex2D(sampler_main, uv + v*offset) * falloff)` along the motion vector. Creates bright persistent trails. The `max()` operation (rather than average) means bright points leave trails without dimming the source. Found in Dancer/Glowsticks, Particles/Points Trails.

### 5. Procedural Cloud Noise
Multi-octave 3D noise via `tex3D(sampler_noisevol_hq, float3(uv, time))` at 4 octaves with 1/f weighting. Creates volumetric cloud/gas/nebula effects. Found in Supernova/Burst, Supernova/Gas.

### 6. Crystal Faceting via Quantized Angles
`floor(atan2(uv.y, uv.x))` quantizes direction into discrete facets. Combined with sin-based domain distortion (`sin(uv * mult)`) to create repeating cells. Found in Sparkle/Jewel.

### 7. Forward Kinematics for Articulated Figures
Full joint-chain animation using sequential rotation matrices. Audio drives joint angles through smooth sinusoidal functions. The wave `sample` parameter doubles as both the "which point along the limb" coordinate and the time-phase offset (via `phs = -sample * 0.2`). Found in Dancer.

### 8. Instanced 3D Shape Systems
`shapecode` with `num_inst=1024` and per-instance 3D position calculation with full rotation/projection. Creates particle clouds, scattered geometry, 3D objects built from small shapes. Found in Sparkle/Explosions, Geometric/Sphere Wild.

### 9. Reaction-Diffusion Self-Organization
Content self-generates from noise through local interaction rules. Audio modulates reaction parameters rather than directly creating content. Found in Reaction (all subcategories).

### 10. Random Walk Audio Brush
Direction accumulator driven by bass vs treble balance. Creates organic drawings that evolve based on the spectral character of the music. Found in Drawing.

### 11. Inverse-Radius Mapping
`rad1 = 0.1/rad` maps the center to infinity and infinity to the center, creating a tunnel/starburst effect when combined with time-based offset scrolling. Found in Sparkle/Explosions, some Supernova.

### 12. Error Diffusion Dithering
`ret += (tex2D(sampler_noise_lq, dither_uv) - 0.5) / 256.0 * 7` eliminates banding artifacts in gradients. Found in many high-quality presets.

### 13. Differential Equation Phase Plots
Lotka-Volterra and Lorenz attractor systems where the per_pixel code or wave per_point code iterates a dynamical system, using the trajectory as a visual element. Found in Hypnotic/Polar Rolling.

### 14. Textured Shape Self-Nesting
Shapes with `textured=1` sample the feedback texture, creating recursive visual nesting (scene-within-scene). This is the foundation of the entire Fractal category.

### 15. Color Wrapping via frac()
`ret = frac(ret - decay)` wraps color values instead of clamping, creating smooth color cycling effects as content decays. Found in some Sparkle presets.

---

## Key Numerical Parameter Ranges

From analysis across all categories:

| Parameter | Typical Range | Purpose |
|-----------|--------------|---------|
| fDecay | 0.5 - 1.0 | 0.5 = aggressive darkening (Jewel), 0.96-0.985 = long trails (Geometric, Supernova), 1.0 = no decay (warp shader handles it) |
| zoom | 0.93 - 1.065 | < 1.0 = zoom out (tunnel), > 1.0 = zoom in (starburst). Often near 1.0 with audio modulation |
| rot | -0.8 - 0.8 | Often 0.0 with per_pixel variation. Large static rot is rare except Sparkle/Explosions |
| warp | 0.01 - 100.0 | Usually small (0.01-0.25). Extreme values (100) used with very slow warpAnimSpeed for subtle displacement |
| fZoomExponent | 1.0 - 13.7 | Usually 1.0. Higher values concentrate zoom near center (used in some Geometric/Spiral presets) |
| sx, sy | -1.0 - 2.0 | sx=-1 for horizontal mirror (Rorschach). sy=2.0 for vertical stretch (Dancer) |
| fVideoEchoAlpha | 0.0 - 0.6 | When > 0, blends a zoomed/flipped copy of the frame (ghosting effect) |

---

## Audio Response Patterns Summary

### Direct Continuous Mapping (Layer 1 equivalent)
- `zoom = zoom + (bass_att - 1) * 0.2` — Bass energy drives zoom
- `rot = rot + 0.05 * sin(fps*100) * q1` where q1 = f(bass, mid, treb) — Rotation rate from combined energy
- `mtime = mtime + pow(mid,2) * 0.01; q_rot = mtime * 0.5` — Accumulated mid energy drives rotation angle
- `gamma = 1 + min(vol*0.8, 1) * 0.7` — Volume drives brightness
- `rad = rad * sounds * 0.6` — Shape radius pulsing with total energy

### Beat/Threshold Detection (Layer 4 equivalent)
Many presets implement their own beat detection in per_frame code:
```
beat = max(max(bass, mid), treb);
avg = avg * dec_slow + beat * (1 - dec_slow);
is_beat = above(beat, 0.5 + avg + peak) * above(time, t0 + 0.2);
peak = is_beat * beat + (1 - is_beat) * peak * dec_med;
```
This is adaptive threshold detection: the running average tracks baseline, `peak` provides a refractory period, and the cooldown (`t0 + 0.2`) prevents re-triggering too fast.

### Spectral Balance Mapping
- `h1 = (bb - mn) / (mx - mn)` — Normalize each band relative to current min/max
- Differences between normalized bands drive slow accumulators
- Creates mappings where visual parameters shift based on which band is *relatively* dominant, not absolute levels

### FPS-Independent Smoothing
Universal pattern: `dec_slow = pow(0.98, 30/fps)` — smoothing rate is 0.98 at 30fps, adjusted for actual framerate. Same formula as Phosphene's approach.

---

## Implications for Phosphene Shader Design

1. **Per-pixel equations map to Metal fragment shader uniforms**: The coarse mesh (32x24) with interpolated zoom/rot/dx/dy is equivalent to evaluating these expressions per-fragment in Metal, which is trivial at modern GPU speeds.

2. **The composite shader is the most creative layer**: Most visual variety comes from UV remapping in the composite pass, not from the warp pass. Phosphene should prioritize a flexible composite/post-processing system.

3. **Shape instances are a particle system**: `num_inst=1024` with per-instance positioning is essentially GPU instanced rendering. Metal mesh shaders or instanced draw calls replicate this directly.

4. **Custom waves are 3D polyline renderers**: The 512-point per_point system with 3D rotation and projection is a CPU-side polyline generator. In Metal, this maps to a vertex shader that takes per-vertex data and does the rotation/projection on GPU.

5. **Reaction-diffusion is the most "generative" technique**: It creates content from nothing. Worth implementing as a Metal compute shader pass that can be mixed with the feedback loop.

6. **The Flexi complex math library is reusable**: Moebius transforms, bipolar coordinates, lens distortion, hex grids — these are self-contained functions that translate directly to Metal shader utility functions.

7. **Audio-weighted time accumulation is universal**: Nearly every preset accumulates `mtime += vol * rate` and uses mtime for animation. This is more organic than raw `time` because it speeds up with volume. Phosphene should expose accumulated-audio-time as a shader uniform alongside wall-clock time.

8. **max() motion blur is cheap and effective**: 4-5 texture reads along the motion vector with `max()` and falloff weights creates convincing trails. Cheaper than true motion blur.
