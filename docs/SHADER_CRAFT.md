# Phosphene — Shader Craft Handbook

**Status:** Draft v0.1. Canonical authoring guide for Phosphene preset shaders. Primary audience: Claude Code sessions authoring new presets or uplifting existing ones. Secondary audience: Matt reviewing the output.

**Scope:** Fidelity. Specifically: how to write Metal shaders that look like they were made in 2026, not 2006. Covers detail cascades, material recipes, lighting recipes, volume and SDF craft, texturing beyond single-octave noise, performance guidance, and a per-preset uplift playbook.

**Out of scope:** Audio routing (that's `CLAUDE.md §Audio Data Hierarchy`), GPU binding contract (that's `CLAUDE.md §GPU Contract Details`), SwiftLint compliance (shader file-length rules are special-cased per §11).

---

## 1. Philosophy

### 1.1 The fidelity problem

Phosphene's engine is modern: Metal 3.1+, deferred G-buffer ray march, IBL, SSGI, MetalFX-upscaling-capable, mesh shaders on M3+, hardware ray tracing via BVH. The engine can render AAA-quality output.

The preset shaders authored so far do not. Six iterations of Volumetric Lithograph, three of Arachne, three of Gossamer. Each iteration fixed a specific bug but none reached the quality bar of a modern ShaderToy top-hit, let alone a shipping game.

The root cause is not hardware, not Metal, not budget. The root cause is **authoring-vocabulary poverty**: the techniques that separate 2026-quality shaders from 2006-quality ones were not documented anywhere Claude Code could read them, and the `ShaderUtilities` library was thin.

This handbook addresses that directly.

### 1.2 The detail cascade principle

Every visible surface in a production-quality shader has **at least four distinct detail scales** layered together. Not one noise function, not two octaves of fBM — four or more distinct authoring layers, each targeted at a different spatial frequency.

Canonical cascade:

1. **Macro form** (unit scale — the whole thing). The SDF geometry or mesh silhouette. What you see from across the room.
2. **Meso variation** (∼0.1–0.3 unit scale). Dents, ridges, strata, folds. The "shape language" beyond primitive.
3. **Micro surface** (∼0.01–0.03 unit scale). Normal-map-level detail. The "texture" in the tactile sense.
4. **Specular breakup** (pixel to sub-pixel scale). Glints, roughness variation, micro-scratches. What makes metals look real.

A preset that skips any of these four reads as primitive, regardless of how clever the macro form is. The Arachne v3 web is a textbook example: beautiful macro form (concentric silk with spiral), no meso (every thread identical), no micro (thread surfaces are constant-albedo tubes), no specular breakup (uniform glow). Reads as clipart.

**Hard rule:** every preset ships with all four cascade layers applied to every primary surface.

### 1.3 The "2026 test"

Before declaring a preset done, ask: does a still frame from this preset look comparable to a still frame from a 2026-released indie game? If the answer is no, you are not done — regardless of how well it animates, how good the audio reactivity is, or how many hours have been spent iterating.

This is the quality bar. Not "better than Milkdrop 1999" (a low bar). Not "good given the constraints" (there are fewer constraints than it feels like). The bar is: comparable to a 2026-released game.

---

## 2. Authoring Workflow

### 2.1 Never author blind

Before a single line of MSL is written:

1. Read `docs/VISUAL_REFERENCES/<preset_name>/README.md`.
2. Study the reference images curated there. The typical preset has 3–5 references; composite presets may require more, with each image earning its place by isolating a distinct trait (per D-065). Each reference has annotations specifying which visual traits are mandatory, which are decorative, and which traits of the image must be *actively disregarded* by Claude Code sessions reading the folder (e.g. the radial vein pattern in a lotus-leaf droplet reference is not a directive about spike arrangement).
3. Write down the four detail-cascade layers you intend to implement. Sketch each as a one-line description referencing specific utility functions from `Shaders/Utilities/`.

Claude Code sessions that skip step 1–2 produce primitive output. Observed on every iteration v1 → v3 of every preset before Phase V. This is `Failed Approach §35` in `CLAUDE.md`.

### 2.2 Coarse-to-fine construction

Never write a finished-looking shader in one pass. The order that consistently produces quality output:

1. **Macro geometry pass.** SDF scene or mesh silhouette. Bounding box, readable composition, one material per region. No detail. Should look like clay maquette. Test in `TestSphere`-style pipeline before going further.
2. **Material pass.** Apply cookbook material recipes from §4 to each region. Still one instance per material — no variation yet.
3. **Meso variation pass.** Add per-primitive variation (tilt, scale, color shift, SDF displacement) so no two instances are identical.
4. **Micro detail pass.** Add detail normals, triplanar texturing, POM where budget allows.
5. **Specular breakup pass.** Roughness variation, grunge, thin-film interference, specular glints.
6. **Atmosphere pass.** Fog, god rays, dust motes, aerial perspective.
7. **Lighting polish.** IBL balance, fill lighting, rim light tuning.
8. **Audio reactivity pass.** Route `FeatureVector` and `StemFeatures` into parameters. Use deviation primitives per `CLAUDE.md §Audio Data Hierarchy` (D-026). Per-frame breathing via `mv_warp` if appropriate (D-027, D-029 constraints apply).
9. **Matt review.** Frame capture compared against reference images. No approval → loop back to whichever pass is weakest.

Passes 1–7 are the fidelity work. Pass 8 is what every prior preset iteration *started* with. The order matters.

### 2.3 Reference-image discipline

Every new preset requires a VISUAL_REFERENCES folder before its first session prompt can be written. Matt owns the references. Photographic references must be sourced from real photography or in-engine capture — AI-generated images are not permitted *except* in the anti-reference slot (`05_anti_*`), under the narrow carve-out described below (per D-065). Claude Code sessions reference them by filename:

```
docs/VISUAL_REFERENCES/arachne/
  README.md
  01_macro_web_geometry.jpg       (annotation: "silk threads ≈1.5 px at 1080p")
  02_meso_per_strand_variation.jpg (annotation: "no two strands identical in tension/sag")
  03_micro_adhesive_droplet.jpg    (annotation: "drops 8–12 px apart on spiral threads")
  04_specular_fiber_highlight.jpg  (annotation: "narrow axial specular along each strand")
  05_anti_reference.jpg            (annotation: "NOT this — flat cylindrical tubes")
```

Session prompts reference images directly: "Implement strand specular per `04_specular_fiber_highlight.jpg`, specifically the narrow axial highlight running along each fiber."

**Anti-reference AI-generation carve-out (per D-065).** The anti-reference slot (`05_anti_*`) may use an AI-generated image when (a) the failure mode being depicted is non-photographable (e.g. "ferrofluid that has lost its Rosensweig spike topology and become a chrome blob" — a phenomenon that does not occur in nature), and (b) sourcing a real-photograph or in-engine v1-baseline alternative is impractical. AI-generated anti-references must:
- Use the `_AIGEN` suffix in the filename (e.g. `05_anti_chrome_blob_AIGEN.jpg`) so the AI provenance is visible in any session prompt that cites the file.
- Carry an annotation stating that *every* trait of the image is anti — there is no partial-trust read of any visual property.
- Be flagged in the README's Provenance section with a planned replacement, typically a v1-baseline frame capture once the preset's first iteration ships.

The carve-out does not extend to any other slot. Real photography or controlled in-engine capture remains mandatory for `01_macro_*` through `04_specular_*`, `06_palette_*`, `07_atmosphere_*`, `08_lighting_*`, and `09_*`.

The lint check at `PhospheneTools/Sources/CheckVisualReferences` (Increment V.5)
verifies that every registered preset has a populated VISUAL_REFERENCES folder and
that filenames follow `docs/VISUAL_REFERENCES/_NAMING_CONVENTION.md`. Run via:

```bash
swift run --package-path PhospheneTools CheckVisualReferences
```

Session prompts SHOULD cite specific reference filenames inline
(e.g. "implement strand specular per `04_specular_fiber_highlight.jpg`").
Reviewers SHOULD reject session prompts for V.7+ that do not cite at least one
reference filename for each major implementation pass.

### 2.4 The rubric

Every preset is gated against a fidelity rubric before certification (§12). Passing compilation and passing `Increment 5.2` invariants are necessary but not sufficient.

---

## 3. Noise Layering

### 3.1 Why single-octave is primitive

A single Perlin or Worley call produces one spatial frequency. Real surfaces have variation across many frequencies simultaneously — you see the macro shape, the meso ripples, the micro grain, all at once. A single-octave noise-textured surface reads as "procedural" in the bad sense: machine-generated rather than physically-derived.

### 3.2 8-octave hero fBM

The workhorse. Eight octaves, per-octave amplitude halving, per-octave frequency doubling, with a rotation between octaves to avoid grid artifacts.

```metal
// From Shaders/Utilities/Noise/FBM.metal (Increment V.1)
float fbm8(float3 p, float H = 0.5) {
    const float3x3 rot = float3x3(
        0.00, 0.80, 0.60,
       -0.80, 0.36,-0.48,
       -0.60,-0.48, 0.64
    );
    float a = 1.0;
    float f = 1.0;
    float sum = 0.0;
    float norm = 0.0;
    for (int i = 0; i < 8; ++i) {
        sum += a * perlin3d(p * f);
        norm += a;
        a *= H;
        f *= 2.0;
        p = rot * p;
    }
    return sum / norm;
}
```

Use for: terrain heightfields, organic surface displacement, cloud density fields.

Cost: ~8× single-octave Perlin. At 1080p budget ~2 ms per screen-space fbm8 call on Tier 2. Avoid inside an inner ray-march loop; compute once per ray hit.

### 3.3 Ridged multifractal for mountainous topology

`fbm8` produces lumpy, rolling shapes — good for hills, bad for mountains. Mountains need ridged noise: sharp crests, valleys, drainage networks.

```metal
// Shaders/Utilities/Noise/RidgedMultifractal.metal (Increment V.1)
float ridged_mf(float3 p, float H = 0.5) {
    float a = 1.0;
    float f = 1.0;
    float sum = 0.0;
    float norm = 0.0;
    for (int i = 0; i < 6; ++i) {
        float n = perlin3d(p * f);
        n = 1.0 - abs(n);       // ridges
        n *= n;                  // sharpen
        sum += a * n;
        norm += a;
        a *= H;
        f *= 2.0;
    }
    return sum / norm;
}
```

Use for: Volumetric Lithograph terrain, Arachne background topology, anywhere you want crests and valleys.

### 3.4 Domain warping

The single highest-leverage noise technique. Warp the input coordinates through another noise field before evaluating the base noise. Produces organic, swirling, liquid forms that straight fBM cannot.

```metal
// Shaders/Utilities/Noise/DomainWarp.metal (Increment V.1)
float warped_fbm(float3 p) {
    float3 q = float3(fbm8(p + float3(0.0, 0.0, 0.0)),
                      fbm8(p + float3(5.2, 1.3, 7.1)),
                      fbm8(p + float3(3.1, 9.7, 2.9)));
    float3 r = float3(fbm8(p + 4.0 * q + float3(1.7, 9.2, 3.4)),
                      fbm8(p + 4.0 * q + float3(8.3, 2.8, 1.1)),
                      fbm8(p + 4.0 * q + float3(4.5, 6.1, 2.3)));
    return fbm8(p + 4.0 * r);
}
```

Use for: any surface that needs to look alive — Ferrofluid Ocean waves, Gossamer silk flow, lichen patches on Fractal Tree bark, Volumetric Lithograph erosion.

Cost: 7 fbm8 calls = 56 Perlin evaluations. Heavy. Compute per-vertex or per-hit, not per-pixel.

### 3.5 Curl noise for fluid flow fields

Curl of a vector-valued noise field is divergence-free: perfect for fluid-like flow without net inflow/outflow. Drives particle velocities, heightfield advection, flow-map UV offsets.

```metal
// Shaders/Utilities/Noise/Curl.metal (Increment V.1)
// Divergence-free 3D curl via central differences on fbm8.
// For curl of (Fx, Fy, Fz):  curl.x = dFz/dy - dFy/dz, etc.
static inline float3 curl_noise(float3 p, float e = 0.01) {
    float inv2e = 0.5 / e;

    float n1 = fbm8(p + float3(0, e, 0)) - fbm8(p - float3(0, e, 0));  // dFz/dy
    float n2 = fbm8(p + float3(0, 0, e)) - fbm8(p - float3(0, 0, e));  // dFy/dz
    float n3 = fbm8(p + float3(e, 0, 0)) - fbm8(p - float3(e, 0, 0));  // dFx/dz
    float n4 = fbm8(p + float3(0, 0, e)) - fbm8(p - float3(0, 0, e));  // dFz/dx
    float n5 = fbm8(p + float3(e, 0, 0)) - fbm8(p - float3(e, 0, 0));  // dFy/dx
    float n6 = fbm8(p + float3(0, e, 0)) - fbm8(p - float3(0, e, 0));  // dFx/dy

    return float3(
        (n1 - n2) * inv2e,   // curl.x = dFz/dy - dFy/dz
        (n3 - n4) * inv2e,   // curl.y = dFx/dz - dFz/dx
        (n5 - n6) * inv2e    // curl.z = dFy/dx - dFx/dy
    );
}
```

Use for: particle flow in Murmuration successors, water advection in Ferrofluid Ocean, smoke/mist advection, Arachne dust-mote drift.

### 3.6 Worley-Perlin blend

Worley (cellular) noise produces distinct features — cells, cracks, spots. Blending Worley into fBM gives "fBM with character" — streaked, veined, marbled.

```metal
// Shaders/Utilities/Noise/Worley.metal (Increment V.1)
static inline float worley_fbm(float3 p) {
    float w = worley3d(p * 2.0).x;   // F1 distance
    float f = fbm8(p);
    return mix(f, w, 0.35);
}
```

Use for: granite/marble/stone, cell-like organic tissue (Arachne carapace), drainage patterns in erosion.

### 3.7 Blue-noise dithering

Per `CLAUDE.md §Texture Binding Layout` texture(8) is 256² IGN (Interleaved Gradient Noise) blue noise. Use it to kill banding in every integration pass:

```metal
// In any integrating pass (SSGI, volumetric, probe sampling)
float dither = blue_noise_tex.sample(sampler, in.uv * screen_size / 256.0).r;
float jittered_t = ray_t + dither * step_size;
```

Blue-noise dithering turns perceptible banding into perceptually-invisible noise. Every volumetric and SSGI pass should use it.

### 3.8 Recipe cheat sheet

| Visual target | Recipe |
|---|---|
| Rolling hills | `fbm8(p * 0.15)` |
| Sharp mountains | `ridged_mf(p * 0.15)` |
| Liquid flow | `warped_fbm(p)` |
| Cells / drainage | `worley_fbm(p * 0.8)` |
| Clouds | `fbm8(p + time * 0.1)`, density-remapped |
| Swirling smoke | `fbm8(p + 2.0 * curl_noise(p + t))` |
| Stone / granite | `worley_fbm(p * 2.0) + 0.2 * fbm8(p * 8.0)` |
| Erosion striations | `ridged_mf(warped_fbm_vec(p))` |

---

## 4. Material Cookbook

Each recipe assumes the preset fragment has access to `FeatureVector& f [[buffer(0)]]`, `StemFeatures& stems [[buffer(3)]]`, and writes to the standard G-buffer layout from `CLAUDE.md §G-Buffer Layout`. Cost estimates are at 1080p on M3 (Tier 2).

Materials are authored as functions returning `MaterialResult`:

```metal
struct MaterialResult {
    float3 albedo;
    float roughness;
    float metallic;
    float3 normal;       // in world space or tangent space per preset convention
    float3 emission;     // HDR (used by PBR composite)
};
```

### 4.1 Polished chrome

**Use for:** Kinetic Sculpture chrome lattice, mirror-bright highlights, Glass Brutalist chrome fixtures.

**Recipe:**

```metal
MaterialResult mat_polished_chrome(float3 wp, float3 n) {
    MaterialResult m;
    m.albedo = float3(0.95);
    m.roughness = 0.03;
    m.metallic = 1.0;
    // Anisotropic streak via tangent-aligned roughness modulation
    float streak = fbm8(wp * 40.0);
    m.roughness += 0.04 * streak;   // break up uniformity
    m.normal = n;
    m.emission = float3(0.0);
    return m;
}
```

Cost: ~0.2 ms. Looks flat without nearby IBL variation — always needs a detailed surrounding.

### 4.2 Brushed aluminum

**Use for:** Kinetic Sculpture brushed lattice, aircraft skins, industrial fixtures.

**Recipe:**

```metal
MaterialResult mat_brushed_aluminum(float3 wp, float3 n, float3 brush_dir) {
    MaterialResult m;
    m.albedo = float3(0.91, 0.92, 0.93);
    // Brush streaks: anisotropic roughness along brush_dir
    float streak_coord = dot(wp, brush_dir);
    float streak = fract(streak_coord * 300.0);
    streak = abs(streak - 0.5);   // triangle wave
    m.roughness = 0.18 + 0.08 * streak;  // 0.10–0.26 striped
    m.metallic = 1.0;
    // Detail normal perturbation along brush direction
    float3 perp = normalize(cross(n, brush_dir));
    m.normal = normalize(n + perp * 0.02 * streak);
    m.emission = float3(0.0);
    return m;
}
```

Cost: ~0.3 ms. The anisotropic streak is the difference between "brushed aluminum" and "flat matte metal."

### 4.3 Silk thread (Marschner-lite fiber BRDF)

**Use for:** Arachne + Gossamer spider silk, any fiber-rendered preset. This is the single biggest fidelity lift for both Arachnid Trilogy presets.

True Marschner is expensive (three lobes, elliptical cross-section). A practical approximation keeps the R (reflection) and TT (transmission-transmission) lobes and fakes TRT as a secondary rim.

**Recipe:**

```metal
struct FiberParams {
    float3 fiber_tangent;     // along the thread
    float3 fiber_normal;      // perpendicular, around which fiber is symmetric
    float azimuthal_r;        // cuticle roughness (longitudinal)
    float azimuthal_tt;       // internal scattering roughness
    float absorption;         // silk absorption along thread
    float3 tint;              // silk tint
};

MaterialResult mat_silk_thread(float3 wp, FiberParams p, float3 L, float3 V) {
    MaterialResult m;
    float3 T = p.fiber_tangent;

    // R lobe: specular cone around T with roughness azimuthal_r
    float cos_theta_i = dot(T, L);
    float cos_theta_o = dot(T, V);
    float theta_h = acos(clamp((cos_theta_i + cos_theta_o) * 0.5, -1.0, 1.0));
    float r_lobe = exp(-theta_h * theta_h / (2.0 * p.azimuthal_r * p.azimuthal_r));

    // TT lobe: transmission-transmission, approximated as back-lit rim
    float backlit = saturate(-dot(T, L) * dot(T, V));
    float tt_lobe = pow(backlit, 1.0 / max(0.01, p.azimuthal_tt));

    m.albedo = p.tint;
    m.roughness = 0.3;
    m.metallic = 0.0;
    m.normal = normalize(p.fiber_normal);
    m.emission = p.tint * (r_lobe * 1.5 + tt_lobe * 0.6);

    return m;
}
```

Cost: ~0.8 ms per hit. Node count makes this more expensive than chrome, but each silk strand is worth it.

**Why this matters for Arachne/Gossamer:** current implementations render silk as constant-albedo cylinders. With Marschner-lite, silk strands exhibit narrow axial specular highlights (the R lobe) and a warm rim on back-lit threads (the TT lobe). This is exactly what you see in a nature-documentary close-up of a real web.

### 4.4 Wet stone

**Use for:** Glass Brutalist concrete after rain, any darkened wet surface.

**Recipe:**

```metal
MaterialResult mat_wet_stone(float3 wp, float3 n, float wetness) {
    MaterialResult m;
    float3 dry_albedo = float3(0.35, 0.32, 0.30);
    float3 wet_albedo = dry_albedo * 0.55;      // wet darkens albedo
    m.albedo = mix(dry_albedo, wet_albedo, wetness);

    // Wet surface: smooth (low roughness) but still dielectric
    m.roughness = mix(0.85, 0.15, wetness);
    m.metallic = 0.0;

    // Detail normal from triplanar fBM for stone surface
    m.normal = triplanar_normal(wp * 3.0, n, 0.08);

    // Clear-coat highlight layer: add glossy specular on top of rough base
    // (handled in PBR composite by boosting specular contribution when wetness > 0.3)
    m.emission = float3(0.0);
    return m;
}
```

Cost: ~0.6 ms. Triplanar is the key — uniplanar stretches on vertical surfaces look wrong.

### 4.5 Frosted glass

**Use for:** Glass Brutalist glass fins, any diffused-light transmitter.

**Recipe:**

```metal
MaterialResult mat_frosted_glass(float3 wp, float3 n) {
    MaterialResult m;
    // High albedo (near white) for diffuse scattering
    m.albedo = float3(0.85, 0.88, 0.90);
    // Moderate roughness — not quite matte, not quite clear
    m.roughness = 0.45;
    m.metallic = 0.0;

    // Frost variation: surface-scale noise perturbs normal
    float3 frost = float3(
        fbm8(wp * 25.0),
        fbm8(wp * 25.0 + float3(13.1, 0.0, 0.0)),
        fbm8(wp * 25.0 + float3(0.0, 17.3, 0.0))
    );
    m.normal = normalize(n + (frost - 0.5) * 0.15);

    // Faint internal scattering — emissive approximation for SSS
    float sss_factor = 0.15;
    m.emission = m.albedo * sss_factor;

    return m;
}
```

Cost: ~0.5 ms. Current Glass Brutalist glass is too clean — frost variation is what sells the diffusion.

Recipe is matched to sandblasted / acid-etched glass aesthetics. For pebbled
or hammered pattern glass — coherent cellular dimples rather than uniform
frost — use `mat_pattern_glass` (§4.5b) instead. Glass Brutalist v2 commits
to the pattern variant per V.12 scope; `mat_frosted_glass` remains canonical
for any preset wanting sandblasted diffusion.

### 4.5b Pattern glass (voronoi cellular)

**Use for:** Glass Brutalist glass fins (per V.12 scope); any architectural
pattern-glass / hammered-glass / pebbled-diffuser surface where the cellular
structure should read as coherent geometry rather than noise.

**Differs from `mat_frosted_glass`** in that diffusion comes from a Voronoi
cellular pattern (each cell a domed dimple separated by a sharp ridge) rather
than fbm-noise normal perturbation. Architecturally this matches pebbled and
hammered patterned glass; the fbm-frost variant matches sandblasted / acid-
etched glass. Pick per preset.

**Recipe:**

```metal
MaterialResult mat_pattern_glass(float3 wp, float3 n) {
    MaterialResult m;
    // Same base optics as mat_frosted_glass, with slightly lower roughness —
    // pattern glass tends to have crisper highlights between cells than frost.
    m.albedo    = float3(0.85, 0.88, 0.90);
    m.roughness = 0.40;
    m.metallic  = 0.0;

    // Sample voronoi_f1f2 at world-position and two ε-offsets so a height
    // gradient can be derived. scale 18 ≈ 3-5 cells per architectural unit
    // at typical viewing distance; tune per preset via uniform if needed.
    // For non-axis-aligned faces, project wp into the fin's face plane
    // before sampling (e.g. wp.yz for X-aligned vertical fins).
    const float scale = 18.0;
    const float eps   = 0.005;
    float2 p  =  wp.xy                       * scale;
    float2 px = (wp.xy + float2(eps, 0.0))   * scale;
    float2 py = (wp.xy + float2(0.0, eps))   * scale;

    VoronoiResult v0 = voronoi_f1f2(p,  4.0);   // Texture/Voronoi.metal
    VoronoiResult vx = voronoi_f1f2(px, 4.0);
    VoronoiResult vy = voronoi_f1f2(py, 4.0);

    // Domed cells: F1 small at cell centre, large at cell edge → invert for
    // height. The (F2 - F1) factor gates the dome down to zero at cell
    // boundaries, producing a sharp inter-cell ridge that catches highlights.
    float h0 = (1.0 - saturate(v0.f1 * scale)) * smoothstep(0.0, 0.04, v0.f2 - v0.f1);
    float hx = (1.0 - saturate(vx.f1 * scale)) * smoothstep(0.0, 0.04, vx.f2 - vx.f1);
    float hy = (1.0 - saturate(vy.f1 * scale)) * smoothstep(0.0, 0.04, vy.f2 - vy.f1);

    float3 height_grad = float3(h0 - hx, h0 - hy, 0.001) * (1.0 / eps);
    m.normal = normalize(n + height_grad * 0.04);

    // Faint internal scattering approximation — same as mat_frosted_glass.
    m.emission = m.albedo * 0.15;

    return m;
}
```

Cost: ~0.5–0.6 ms (three `voronoi_f1f2` calls at ~0.11 ms each plus arithmetic).
The cell-edge ridge — driven by the smoothstep on F2−F1 — is what sells this
as patterned rather than noisy; a flat dome without the ridge collapses back
toward fbm-frost in appearance.

### 4.6 Ferrofluid (Rosensweig spikes)

**Use for:** Ferrofluid Ocean. This preset's fidelity hinges on this recipe.

Ferrofluid surfaces under magnetic field form a lattice of conical spikes (Rosensweig instability). The spike array is not perfectly regular — it has hexagonal tendencies with domain defects. Between the spikes the surface is nearly mirror-metal.

**Recipe for the SDF:**

```metal
// Field at position p: returns height displacement.
// Uses voronoi_f1f2 (Geometry/Voronoi-based) for authentic Rosensweig cell centres.
// `field_strength` ∈ [0,1]; route from stems.bass_energy_dev.
// `t` = FeatureVector.accumulated_audio_time.
static inline float ferrofluid_field(float3 p, float field_strength, float t) {
    float2 xz = p.xz;
    // Voronoi cell centres — gives proper Rosensweig hex-like distribution.
    VoronoiResult v = voronoi_f1f2(xz, 4.0);   // from Texture/Voronoi.metal
    // Per-cell jitter from fBM seeded by cell centre.
    float jitter = fbm8(float3(v.pos * 2.0, 0.0)) * 0.3;
    float d = v.f1 + jitter * 0.05;
    // Conical spike profile with bell-curve falloff.
    float spike = exp(-d * d * 40.0);
    // Time-animated per-cell phase: cell hash gives unique phase per spike.
    float cellPhase = float(v.id & 0xFFFF) * (6.283185 / float(0xFFFF));
    spike *= 0.5 + 0.5 * sin(t * 0.8 + cellPhase);
    return spike * field_strength * 0.15;
}

static inline float sdf_ferrofluid(float3 p, float field_strength, float t) {
    float base_y = 0.0;
    float spikes  = ferrofluid_field(p, field_strength, t);
    return p.y - (base_y + spikes);
}
```

**Recipe for the material:**

```metal
MaterialResult mat_ferrofluid(float3 wp, float3 n) {
    MaterialResult m;
    // Deep black with hint of blue in highlights (magnetic fluid is oil-based, dark)
    m.albedo = float3(0.02, 0.03, 0.05);
    m.roughness = 0.08;   // near-mirror
    m.metallic = 1.0;     // F0 behaves metallic
    // Anisotropy along flow direction: if we have one
    m.normal = n;
    m.emission = float3(0.0);
    return m;
}
```

Cost: spike field ~1.5 ms, material ~0.2 ms. The spike lattice is animation-heavy — route `field_strength` from `stems.bass_energy_dev` so bass pulses drive spike height.

### 4.7 Bark

**Use for:** Fractal Tree bark. Current FT presets render bare geometry.

**Recipe:**

```metal
MaterialResult mat_bark(float3 wp, float3 n, float3 fiber_up) {
    MaterialResult m;
    // Base color: warm brown with variation
    float3 base = float3(0.18, 0.11, 0.07);
    float3 lichen = float3(0.35, 0.42, 0.22);

    // Lichen patches via Worley
    float w = worley3d(wp * 0.6).x;
    float lichen_mask = smoothstep(0.25, 0.40, w);
    m.albedo = mix(base, lichen, lichen_mask * 0.4);

    // Vertical fiber displacement: ridges along fiber_up
    float fiber_coord = dot(wp, fiber_up);
    float ridges = abs(fract(fiber_coord * 8.0) - 0.5);
    ridges = smoothstep(0.1, 0.4, ridges);

    // Overall bark normal perturbation
    float3 horizontal = normalize(cross(fiber_up, n));
    m.normal = normalize(n + horizontal * ridges * 0.35);
    // Micro detail
    m.normal = triplanar_detail_normal(m.normal, wp * 30.0, 0.04);

    m.roughness = 0.85 + 0.1 * fbm8(wp * 5.0);
    m.metallic = 0.0;
    m.emission = float3(0.0);
    return m;
}
```

Cost: ~0.9 ms. Ridges + lichen + triplanar detail is what separates "bark" from "brown cylinder."

### 4.8 Translucent leaf

**Use for:** Fractal Tree foliage. Requires SSS approximation.

**Recipe:**

```metal
MaterialResult mat_leaf(float3 wp, float3 n, float3 V, float3 L) {
    MaterialResult m;
    // Chlorophyll green with vein variation
    float3 base = float3(0.12, 0.25, 0.08);
    float3 vein = float3(0.20, 0.35, 0.12);
    float vein_mask = smoothstep(0.45, 0.55, fbm8(wp * 12.0));
    m.albedo = mix(base, vein, vein_mask);

    // Back-lit SSS: leaf glows warmly when light shines through
    float VdotL = dot(V, -L);
    float sss = saturate(VdotL);
    sss = pow(sss, 3.0);
    float3 sss_tint = float3(0.6, 0.8, 0.2);
    m.emission = sss_tint * sss * 0.8;

    m.roughness = 0.5;
    m.metallic = 0.0;
    m.normal = n;
    return m;
}
```

Cost: ~0.4 ms. The back-lit SSS term is what sells "leaf" vs "green plastic."

### 4.9 Volumetric cloud

**Use for:** Murmuration sky backdrop, Volumetric Lithograph aerial perspective, any atmospheric preset.

Clouds are not a surface material — they're volumetric. Rendered via ray-march through a density field with Henyey-Greenstein phase function.

```metal
float3 sample_cloud(float3 ro, float3 rd, float3 light_dir, float3 light_color) {
    float3 col = float3(0.0);
    float transmittance = 1.0;
    float t = 0.0;
    for (int i = 0; i < 64; ++i) {
        float3 p = ro + rd * t;
        float density = cloud_density_field(p);   // fbm8 + remap
        if (density > 0.01) {
            // Sample light through cloud to get self-shadow
            float light_march = 0.0;
            for (int j = 0; j < 6; ++j) {
                float3 lp = p + light_dir * (float(j) * 0.2);
                light_march += cloud_density_field(lp);
            }
            float shadow = exp(-light_march * 0.5);
            // Henyey-Greenstein phase (g = 0.2 for forward scattering)
            float cos_theta = dot(rd, light_dir);
            float phase = (1.0 - 0.04) / pow(1.0 + 0.04 - 0.4 * cos_theta, 1.5);
            col += transmittance * density * shadow * phase * light_color * 0.05;
            transmittance *= exp(-density * 0.1);
            if (transmittance < 0.01) break;
        }
        t += 0.15;
    }
    return col;
}
```

Cost: heavy — ~3 ms per full-screen cloud pass at 1080p on Tier 2. Sample half-res and upscale with MetalFX Temporal if frame budget tight.

### 4.10 Gold

`Materials/Metals.metal:mat_gold` — warm yellow metallic with fine scratch normal variation.

```metal
// Caller responsibilities: none.
// Exposure should be calibrated for IBL at scene_ambient ≈ 0.06 — gold blows out at > 0.15.
MaterialResult mat_gold(float3 wp, float3 n) {
    MaterialResult m;
    m.albedo   = float3(1.0, 0.78, 0.34);
    m.roughness = 0.15;
    m.metallic  = 1.0;
    // Fine scratch fBM at 50× scale, amplitude 0.03 — breaks "liquid gold" uniformity.
    float3 scratch = float3(
        fbm8(wp * 50.0),
        fbm8(wp * 50.0 + float3(7.3, 0.0, 0.0)),
        fbm8(wp * 50.0 + float3(0.0, 3.7, 0.0))
    );
    m.normal   = normalize(n + (scratch - 0.5) * 0.03);
    m.emission = float3(0.0);
    return m;
}
```

### 4.11 Copper with patina

`Materials/Metals.metal:mat_copper` — warm copper on exposed peaks, teal verdigris patina in crevices.

```metal
// ao ∈ [0, 1]: AO = 0 → occluded (more patina), AO = 1 → exposed (clean copper).
// If AO unavailable, pass 0.5 for a mid-blend.
MaterialResult mat_copper(float3 wp, float3 n, float ao) {
    MaterialResult m;
    float3 copper_albedo = float3(0.95, 0.60, 0.36);
    float3 patina_albedo = float3(0.15, 0.55, 0.45);

    // worley_fbm range ≈ [-0.65, 0.79]; threshold at 0.1–0.3 captures upper ~30%.
    float w = worley_fbm(wp * 2.0);
    float patina_mask = smoothstep(0.10, 0.30, w) * (1.0 - ao);

    m.albedo    = mix(copper_albedo, patina_albedo, patina_mask);
    m.roughness = mix(0.25, 0.70, patina_mask);
    m.metallic  = mix(1.0,  0.0,  patina_mask);
    m.normal    = n;
    m.emission  = float3(0.0);
    return m;
}
```

### 4.12 Velvet (retro-reflective fuzz)

`Materials/Organic.metal:mat_velvet` — Oren-Nayar diffuse with Fresnel-driven fuzz term (Increment V.4).

```metal
// velvet_color: fabric colour. NdotV ∈ [0,1]: view-incidence cosine.
// sigma = 0.35 (standard velvet roughness — produces visible retro-reflective lobe).
MaterialResult mat_velvet(float3 wp, float3 n, float3 velvet_color, float NdotV) {
    MaterialResult m;
    m.albedo    = velvet_color;
    m.roughness = 0.90;   // diffuse base is matte
    m.metallic  = 0.0;
    m.normal    = n;

    // Oren-Nayar at sigma=0.35 is approximated by the lambert base above.
    // Fuzz term: brightens at grazing angles (opposite of Fresnel).
    float fuzz = pow(1.0 - NdotV, 2.0);
    m.emission = velvet_color * fuzz * 0.5;
    return m;
}
```

### 4.13 Ceramic (clear-coat)

`Materials/Dielectrics.metal:mat_ceramic` — saturated diffuse glaze base; clear-coat in lighting stage.

```metal
// base_color: the saturated clay/glaze colour.
// Note: the true two-lobe clear-coat (roughness_coat=0.05, F0=0.04) must be added
// in the PBR lighting composite — MaterialResult's single roughness field models
// the diffuse scatter only.
MaterialResult mat_ceramic(float3 wp, float3 n, float3 base_color) {
    MaterialResult m;
    m.albedo    = base_color;
    m.roughness = 0.6 + fbm8(wp * 8.0) * 0.04;   // subtle surface variation
    m.roughness = clamp(m.roughness, 0.0, 1.0);
    m.metallic  = 0.0;
    m.normal    = n;
    m.emission  = float3(0.0);
    return m;
}
```

### 4.14 Ocean water

`Materials/Exotic.metal:mat_ocean` — Fresnel-weighted specular, deep-water absorption, foam on crests.

```metal
// NdotV ∈ [0,1]: view-incidence cosine.
// depth ∈ [0,1]: depth below wave crest (0 = crest/foam, 1 = trough).
//   Callers compute from wave geometry (displacement derivatives).
// Gerstner-wave displacement and capillary ripples are SDF/geometry concerns
// at the preset level (§7). This function handles material properties only.
MaterialResult mat_ocean(float3 wp, float3 n, float NdotV, float depth) {
    MaterialResult m;
    float foam_mask    = smoothstep(0.10, 0.35, 1.0 - depth);
    float3 water_albedo = mix(float3(0.02, 0.06, 0.12),   // deep
                              float3(0.07, 0.18, 0.28),   // shallow
                              (1.0 - depth) * 0.6);
    m.albedo    = mix(water_albedo, float3(0.92, 0.94, 0.96), foam_mask);
    m.roughness = mix(0.08, 0.85, foam_mask);
    m.metallic  = 0.0;
    float3 ripple = float3(fbm8(wp.xzy * 8.0), fbm8(wp.xzy * 8.0 + float3(4.3,0,0)),
                           fbm8(wp.xzy * 8.0 + float3(0,8.7,0)));
    m.normal    = normalize(n + (ripple - 0.5) * 0.04 * (1.0 - foam_mask));
    m.emission  = float3(0.0);
    return m;
}
```

### 4.15 Ink (2D stylized)

`Materials/Exotic.metal:mat_ink` — flat emissive with curl-noise flow-field UV distortion.

```metal
// ink_color: ink tint (saturated colors read best).
// flow_uv: caller-computed distorted UV from a flow-map pass, or wp.xy/scale.
// t: accumulated audio time (FeatureVector.accumulated_audio_time).
MaterialResult mat_ink(float3 wp, float3 n, float3 ink_color, float2 flow_uv, float t) {
    MaterialResult m;
    float3 curl        = curl_noise(float3(flow_uv, t * 0.3));
    float2 distorted   = flow_uv + curl.xy * 0.06;
    float  density     = smoothstep(0.3, 0.7,
                             fbm8(float3(distorted * 3.0, t * 0.05)) * 0.5 + 0.5);
    m.albedo    = float3(0.0);   // emissive-only
    m.roughness = 0.0;
    m.metallic  = 0.0;
    m.normal    = n;
    m.emission  = ink_color * density;
    return m;
}
```

### 4.16 Granite

`Materials/Exotic.metal:mat_granite` — Worley-Perlin speckle over three colour stops, triplanar normal.

```metal
// Caller responsibilities: none.
// Three colour stops: dark matrix / warm feldspar / bright mica.
// worley_fbm range ≈ [-0.65, 0.79]; mica isolated via high-freq fbm8 at separate scale.
MaterialResult mat_granite(float3 wp, float3 n) {
    MaterialResult m;
    float w           = worley_fbm(wp * 2.0);
    float mask_dark   = smoothstep(-0.35, 0.0, w);
    float mica_t      = fbm8(wp * 10.0 + float3(3.7, 9.1, 6.3)) * 0.5 + 0.5;
    float mask_mica   = smoothstep(0.70, 0.90, mica_t);

    float3 color = mix(float3(0.08, 0.08, 0.10),   // dark matrix
                       float3(0.58, 0.50, 0.44),   // feldspar
                       mask_dark);
    color = mix(color, float3(0.82, 0.80, 0.76), mask_mica);   // mica glints

    m.albedo    = color;
    m.roughness = clamp(0.50 + 0.70 * fbm8(wp * 5.0), 0.08, 0.92);
    m.metallic  = 0.0;
    m.normal    = triplanar_detail_normal(n, wp * 4.0, 0.05);
    m.emission  = float3(0.0);
    return m;
}
```

### 4.17 Marble veining

`Materials/Exotic.metal:mat_marble` — curl-noise-warped Perlin veins, sharp bimodal colour split.

```metal
// Caller responsibilities: none.
// fbm8 output ≈ [-1, 1]; smoothstep centred at 0 gives correct bimodal split.
// Threshold (−0.05, 0.05) — NOT (0.48, 0.52) which assumes [0,1] range.
MaterialResult mat_marble(float3 wp, float3 n) {
    MaterialResult m;
    float3 warped   = wp + curl_noise(wp * 1.2) * 0.35;
    float  vein_val = fbm8(warped * 2.5);
    float  vein_mask = smoothstep(-0.05, 0.05, vein_val);   // bimodal split

    m.albedo    = mix(float3(0.90, 0.88, 0.85),   // near-white matrix
                      float3(0.15, 0.08, 0.22),   // deep violet vein
                      vein_mask);
    m.roughness = mix(0.30, 0.55, vein_mask);
    m.metallic  = 0.0;
    // Subtle SSS: luminous translucency in back-lit configuration (matrix only).
    m.emission  = float3(0.90, 0.88, 0.85) * (1.0 - vein_mask) * 0.06;
    m.normal    = n;
    return m;
}
```

### 4.18 Bioluminescent chitin

`Materials/Organic.metal:mat_chitin` — near-black carapace with thin-film iridescence and rim glow.

```metal
// VdotH ∈ [0,1]: view·half-vector (Fresnel input for thin-film).
// NdotV ∈ [0,1]: view incidence cosine (rim emission scale).
// thickness_nm: film thickness in nm (150–400; 200=blue, 300=rainbow, 400=neutral).
// Perfect for the Arachne spider easter-egg carapace (D-040).
MaterialResult mat_chitin(float3 wp, float3 n, float VdotH, float NdotV, float thickness_nm) {
    MaterialResult m;
    m.albedo    = float3(0.02, 0.025, 0.03);
    m.roughness = 0.2;
    m.metallic  = 0.0;
    m.normal    = n;
    // Thin-film iridescence from V.1 PBR/Thin.metal.
    float3 iri = thinfilm_rgb(VdotH, thickness_nm, 1.55, 1.0);
    float  thk_var = fbm8(wp * 15.0) * 50.0;
    iri = mix(iri, thinfilm_rgb(VdotH, thickness_nm + thk_var, 1.55, 1.0), 0.4);
    // Rim emission: bioluminescent glow at silhouette edges.
    float  rim  = pow(1.0 - NdotV, 3.0);
    m.emission  = iri * 0.5 + float3(0.3, 0.8, 0.4) * rim * 0.6;
    return m;
}
```

### 4.19 Sand with glints

`Materials/Exotic.metal:mat_sand_glints` — warm sand base with hash-lattice specular sparkle (Increment V.4).

```metal
// Caller responsibilities: none.
// Glints modelled as rare isolated highlight cells in a hash lattice at 500× scale.
// wp * 500.0 gives one glint cell per ~2mm of world space.
MaterialResult mat_sand_glints(float3 wp, float3 n) {
    MaterialResult m;
    m.albedo    = float3(0.85, 0.70, 0.50);
    m.roughness = 0.90;
    m.metallic  = 0.0;
    m.normal    = triplanar_detail_normal(n, wp * 8.0, 0.04);

    // Hash-lattice glint: rare cells (~0.8%) get a near-mirror micro-facet.
    // hash_f01_3 maps float3 → [0,1]; floor(wp*500) = one cell ≈ 2mm world-space.
    float glint_hash = hash_f01_3(floor(wp * 500.0));
    float glint_mask = step(0.992, glint_hash);
    m.roughness  = mix(m.roughness, 0.05, glint_mask);
    m.emission   = float3(1.0) * glint_mask * 2.0;   // HDR sparkle
    return m;
}
```

### 4.20 Concrete (triplanar POM)

`Materials/Dielectrics.metal:mat_concrete` — gray base with worley variation, POM depth, grunge overlay (Increment V.4).

```metal
// Caller responsibilities:
//   height_tex: a height texture sampled at wp UVs, or pass a null-equivalent
//     and use the procedural fallback below.
//   samp: bilinear sampler.
//   view_ts: view direction in tangent space (from ws_to_ts()).
MaterialResult mat_concrete(float3 wp, float3 n,
                             texture2d<float> height_tex, sampler samp, float3 view_ts) {
    MaterialResult m;
    // Base: cool gray with Worley-driven aggregate variation.
    float w     = worley_fbm(wp * 1.5) * 0.5 + 0.5;    // remap ≈[-0.65,0.79] → [0,1]
    m.albedo    = float3(0.42, 0.42, 0.41) + (w - 0.5) * 0.08;
    m.roughness = 0.88;
    m.metallic  = 0.0;

    // POM displacement from procedural height (fbm8-based).
    // Use parallax_occlusion() from PBR/POM.metal when a real height tex is available.
    // Procedural fallback: perturb normal from fbm8 height field.
    float h0 = fbm8(wp * 5.0);
    float hx = fbm8(wp * 5.0 + float3(0.005, 0, 0));
    float hy = fbm8(wp * 5.0 + float3(0, 0.005, 0));
    float3 height_grad = float3(h0 - hx, h0 - hy, 0.001) * 8.0;
    m.normal = normalize(n + height_grad * 0.12);

    // Grunge overlay: fbm8 at different scale multiplied in.
    float grunge = fbm8(wp * 12.0 + float3(17.3, 5.1, 9.7)) * 0.5 + 0.5;
    m.albedo    *= (0.85 + grunge * 0.25);

    m.emission = float3(0.0);
    return m;
}

---

## 5. Lighting Recipes

### 5.1 Three-point classical

**Use for:** any preset with distinct subjects (Arachne spider, Fractal Tree branches, Kinetic Sculpture).

```json
{
  "scene_lights": [
    { "position": [ 3.0, 4.0, 2.0 ], "color": [1.00, 0.92, 0.80], "intensity": 3.0 },
    { "position": [-2.0, 1.5, 3.5 ], "color": [0.50, 0.70, 1.00], "intensity": 1.2 },
    { "position": [ 0.0, 3.0,-4.0 ], "color": [1.00, 0.65, 0.40], "intensity": 0.8 }
  ]
}
```

Key = warm from above-right (3.0 intensity). Fill = cool from above-left (1.2). Rim = warm from behind (0.8). IBL ambient adds overall soft wash.

### 5.2 Single-directional + strong IBL

**Use for:** outdoor / terrain presets (Volumetric Lithograph, Ferrofluid Ocean).

Single light from sun angle, IBL does the heavy lifting. Tint IBL ambient per mood valence via `lightColor` multiplier (existing D-022 behavior). Keep scene_ambient ∼0.06 so shadows have depth.

### 5.3 Bioluminescent (rim + back-lit SSS)

**Use for:** Arachne spider easter-egg, Gossamer active emission state.

Minimal direct light. Each emissive surface acts as a light source (emission term). Add screen-space bloom to spread emission beyond geometry boundaries. For subjects with SSS (silk, chitin), back-position a soft area light so SSS pass produces rim-ward glow.

### 5.4 Underwater / submerged

**Use for:** hypothetical Ferrofluid Ocean viewed from below; any preset aiming for depth-of-vision distortion.

Directional key from above with cyan tint (`float3(0.4, 0.85, 0.95)`). Strong fog (`fog_factor = 0.08`, `fog_far = 25`). Caustic patterns projected onto surfaces via screen-space caustic texture modulated by `fbm8(p + t * 0.1)`. Depth-of-field post for far objects.

### 5.5 Night-city ambient

**Use for:** presets aiming for urban / neon vibe. Glass Brutalist could push this direction.

Multiple low-intensity colored point lights (magenta, cyan, deep orange) spread through the scene. High bloom threshold so only light sources and direct reflections bloom. IBL environment is dark-sky `float3(0.03, 0.03, 0.08)`. Reduce scene_ambient to 0.02.

### 5.6 Golden hour

**Use for:** Volumetric Lithograph alternate palette; Murmuration warm-valence skies.

Directional light low in sky (y=0.2), warm orange (`float3(1.0, 0.55, 0.25)`), high intensity (4.0). IBL ambient tinted warm. Long shadows via low light angle. Atmospheric fog density 0.02–0.04 with strong Rayleigh-scattering tint: `fog_color = lerp(warm_orange, cool_blue, fog_depth_factor)`.

### 5.7 Lighting as audio reactive

Modulate light properties per music rather than geometry per music (D-020 principle — architecture stays solid, light moves).

| Audio | Light property | Example |
|---|---|---|
| `f.bass_att_rel` | Key light intensity (±10%) | Kick drives slow brightness breathing |
| `stems.drums_beat` | Rim light position orbit | Rim sweeps around subject on each beat |
| `f.valence` | Key light color temperature | Warm on major key, cool on minor |
| `f.arousal` | IBL ambient strength | High energy = brighter ambient |
| `stems.vocals_energy_dev` | Fill light pulse | Vocal presence brightens fill |

---

## 6. Volume and Participating Media

### 6.1 The ground-fog recipe

Every ray-march preset should have at least this level of atmosphere. Hero geometry without air fades to aerial-perspective color with depth.

```metal
// Volume/ParticipatingMedia.metal — apply_fog (snake_case alias, Increment V.4)
// Legacy camelCase equivalent: fog(color, fogColor, dist, density) in ShaderUtilities.metal.
static inline float3 apply_fog(float3 color, float depth,
                                float3 fog_color, float fog_density) {
    float transmittance = exp(-depth * fog_density);
    return mix(fog_color, color, transmittance);
}
```

Set `fog_color` to match the scene's sky or horizon color, not gray. Grey fog looks like a printing defect.

### 6.2 Volumetric light shafts (god rays)

**Use for:** Glass Brutalist through-window lighting, any preset with dramatic directional light through a structured environment.

`Volume/LightShafts.metal` provides two approaches:

**Screen-space radial blur** (cheap, direct-pass presets): accumulate radially toward the projected sun UV using the existing rendered scene as an occlusion mask.

```metal
// Volume/LightShafts.metal (Increment V.2)

// Get the UV to sample at step i (0-indexed) of a radial blur toward sunUV.
static inline float2 ls_radial_step_uv(float2 uv, float2 sunUV, int step, int totalSteps);

// Contribution of one step given a pre-sampled occlusion value [0=shadow, 1=lit].
static inline float ls_radial_accumulate_step(float occlusion, float decay, float weight, int step);

// Simple usage (fragment body):
//   float2 sunSS = ls_world_to_ndc(viewProj, lightWorldPos);  // project light to UV
//   float shafts = 0.0;
//   for (int i = 0; i < 32; i++) {
//       float2 sUV  = ls_radial_step_uv(uv, sunSS, i, 32);
//       float  occ  = sceneTex.sample(s, sUV).a;   // use alpha or luma as mask
//       shafts += ls_radial_accumulate_step(occ, 0.95, 0.02, i);
//   }
//   finalColor += lightColor * shafts * ls_intensity_audio(0.3, midRel);
```

**Ray-march shadow-volume** (accurate, ray-march presets): step from each visible point toward the light, accumulating density from `vol_density_fbm`.

```metal
// March from p toward lightDir, return shadow factor [0,1].
// steps = 8–16 (cheap shadow rays acceptable for atmospheric quality).
static inline float ls_shadow_march(float3 p, float3 lightDir,
                                    float tMax, int steps, float sigma);

// Sun disk + soft corona (add to final color for miss-rays or sky pixels).
static inline float3 ls_sun_disk(float3 rd, float3 sunDir, float3 sunColor);

// Intensity scaled by midRel — shafts brighten on vocal/melody presence.
static inline float ls_intensity_audio(float baseIntensity, float midRel);
```

Cost: screen-space ≈ 0.5 ms (32 samples); ray-march shadow ≈ 1.5 ms (48 steps). Sample at half-res + upscale if budget tight.

**Sky-only-fragment variant (no occlusion mask):** when the shaft is drawn into a backdrop fragment that has no scene texture to sample (Drift Motes' `drift_motes_sky_fragment` is the reference implementation, DM.2), substitute a perpendicular-distance cone mask for the per-step occlusion read. At each `ls_radial_step_uv` sample, evaluate `1 - smoothstep(0, coneHalfWidth, perpFromAxis)` where `perpFromAxis` is the perpendicular distance from the sample UV to the shaft's central axis (the line from `sunUV` through frame centre, or any anchor of the shader's choice). `coneHalfWidth` typically widens with along-axis distance from the sun (`0.04 + 0.12 * along` in Drift Motes). The accumulator otherwise behaves identically. Pair with `dm_pitch_hue` (engine-library, see `ParticlesDriftMotes.metal`) when the mote / sprite hue should ride the recent vocal melody at emission time — D-019 stem-warmup blend handles the cold-stems window.

### 6.3 Dust motes

**Use for:** Arachne spider easter-egg reveal, Gossamer bioluminescent ambient, any scene that wants air-as-material.

`Volume/ParticipatingMedia.metal` provides front-to-back integration for procedural dust/mist volumes:

```metal
// Volume/ParticipatingMedia.metal (Increment V.2)

struct VolumeSample { float3 color; float transmittance; };
static inline VolumeSample vol_sample_zero();

// Density field options (choose based on desired look):
static inline float vol_density_fbm(float3 p, float scale, int octaves);     // heterogeneous mist
static inline float vol_density_height_fog(float3 p, float scale, float falloff); // floor fog
static inline float vol_density_sphere(float3 p, float3 c, float r);         // blob of haze
static inline float vol_density_cloud(float3 p, float scale, float coverage); // wispy clouds

// Accumulate one step (front-to-back). Call in a ray-march loop:
//   VolumeSample s = vol_sample_zero();
//   for (int i = 0; i < 32; i++) {
//       float3 pos = ro + rd * (tMin + stepLen * (float(i) + 0.5));
//       float  den = vol_density_fbm(pos * 3.0 + curl_noise(pos) * 0.4, 1.0, 3);
//       den *= smoothstep(0.0, 0.05, bassRel);   // swell on transients
//       s = vol_accumulate(s, pos, rd, den, stepLen, lightDir, lightColor, 0.1);
//       if (s.transmittance < 0.01) break;
//   }
//   float3 dustColor = s.color + background * s.transmittance;
static inline VolumeSample vol_accumulate(VolumeSample s, float3 p, float3 rd,
    float density, float stepLen, float3 lightDir, float3 lightColor, float sigma);
```

**Approach A (compute particles)**: 5000–20000 motes advected by `curl_noise`, rendered as sprite quads. Lit by scene lights via Lambert. Cost: 2–3 ms.

**Approach B (screen-space)**: sample a 2D noise texture offset by `time * drift_velocity`, threshold for sparkle locations, add to bloom input. Cost: <0.5 ms. Adequate for subtle ambient sparkle.

Both visibly upgrade "empty air" to "inhabited space." Approach B is recommended unless the motes need to respond to geometry.

### 6.4 Volumetric bloom (shaped)

The default `PostProcessChain` bloom (ACES composite + Gaussian pyramid) is adequate but uniform. Shaped bloom — where high-intensity pixels bloom more aggressively along specific directions — is what makes "bright emissive" look like "actual light source."

Two shaping approaches:

- **Anamorphic streaks**: horizontal stretch of bloom, 3× wider than vertical. Instant sci-fi look.
- **Star-point spikes**: 4-point or 6-point spikes extending from brightest pixels. Photographic lens flare aesthetic.

Both are ~0.3 ms additions to the existing bloom chain. Implement as optional flags per-preset in `PresetDescriptor`.

---

## 7. SDF Craft

### 7.1 Smooth union with multi-node blending

`op_smooth_union` as commonly written blends two SDFs. Most ray-march scenes need to blend N SDFs (N > 2) without nesting binary unions (which causes visible triple-points).

Metal fragment shaders cannot take pointer arrays, so the utility provides fixed-arity variants using log-sum-exp exponential smooth-min:

```metal
// Geometry/SDFBoolean.metal — op_blend_4, op_blend_8, op_blend (Increment V.2)

// 2-distance blend (degrades to min() at k < 0.001)
static inline float op_blend(float a, float b, float k) {
    if (k < 0.001) return min(a, b);
    float m   = min(a, b);
    float sum = exp((m - a) / k) + exp((m - b) / k);
    return m - k * log(sum);
}

// 4-distance blend — covers most preset use cases
static inline float op_blend_4(float d0, float d1, float d2, float d3, float k) {
    float m   = min(min(d0, d1), min(d2, d3));
    float sum = exp((m-d0)/k) + exp((m-d1)/k)
              + exp((m-d2)/k) + exp((m-d3)/k);
    return m - k * log(sum);
}

// 8-distance blend — web intersections, complex multi-primitive scenes
static inline float op_blend_8(
    float d0, float d1, float d2, float d3,
    float d4, float d5, float d6, float d7, float k
) {
    float m   = min(min(min(d0,d1),min(d2,d3)), min(min(d4,d5),min(d6,d7)));
    float sum = exp((m-d0)/k) + exp((m-d1)/k) + exp((m-d2)/k) + exp((m-d3)/k)
              + exp((m-d4)/k) + exp((m-d5)/k) + exp((m-d6)/k) + exp((m-d7)/k);
    return m - k * log(sum);
}
```

Use for: Murmuration flock clustering, Arachne web intersections (where radial meets spiral meets hub), organic tendril structures.

### 7.2 Proper displacement (Lipschitz-aware)

Displacement adds surface detail but can break sphere-tracing if displacement amplitude is large relative to feature size. The fix is to scale the returned distance by a safety factor.

```metal
float sd_displaced(float3 p, float base_sdf, float displacement, float safety = 0.6) {
    return (base_sdf - displacement) * safety;
}
```

Safety factor 0.6 is standard. Can tune down to 0.4 for high-frequency displacement, up to 0.8 for gentle.

### 7.3 Tetrahedral normal calculation

The cheapest high-quality SDF normal: sample four points in tetrahedral arrangement, combine.

```metal
// Geometry/RayMarch.metal:ray_march_normal_tetra (Increment V.2)
// Replace sd_sphere(q, 1.0) with your sceneSDF(q) in fragment shaders.
static inline float3 ray_march_normal_tetra(float3 p, float eps) {
    const float2 k = float2(1.0, -1.0);
    return normalize(
        k.xyy * sd_sphere(p + k.xyy * eps, 1.0) +
        k.yyx * sd_sphere(p + k.yyx * eps, 1.0) +
        k.yxy * sd_sphere(p + k.yxy * eps, 1.0) +
        k.xxx * sd_sphere(p + k.xxx * eps, 1.0)
    );
}
```

Four scene evaluations. Use this, not the six-tap central difference.

Practical use in a preset fragment shader:
```metal
// Inline the SDF call directly — Metal fragment shaders cannot pass function pointers.
float3 n = normalize(
    float2(1,-1).xyy * sceneSDF(p + float2(1,-1).xyy * 0.001) +
    float2(1,-1).yyx * sceneSDF(p + float2(1,-1).yyx * 0.001) +
    float2(1,-1).yxy * sceneSDF(p + float2(1,-1).yxy * 0.001) +
    float2(1,-1).xxx * sceneSDF(p + float2(1,-1).xxx * 0.001)
);
```

### 7.4 Adaptive sphere tracing

Fixed-step ray march burns cycles. Sphere tracing is the standard SDF march. Adaptive sphere tracing further accelerates by over-stepping in open space via a configurable relaxation factor.

```metal
// Geometry/RayMarch.metal:RayMarchHit + ray_march_adaptive (Increment V.2)
struct RayMarchHit {
    float distance;  // t along the ray (world position = ro + rd * hit.distance)
    int   steps;
    bool  hit;
};

// gradFactor: 0.0 = standard sphere tracing; 0.5 = 50% over-relaxed (recommended).
// Replace sd_sphere(p, 1.0) with your sceneSDF(p) when copying into fragment shaders.
static inline RayMarchHit ray_march_adaptive(
    float3 ro, float3 rd,
    float tMin, float tMax,
    int   maxSteps,
    float hitEps,
    float gradFactor
) {
    RayMarchHit result = { 0.0, 0, false };
    float omega = 1.0 + gradFactor;
    float t = tMin;
    for (int i = 0; i < maxSteps && t < tMax; i++) {
        float d = sd_sphere(ro + rd * t, 1.0);  // REPLACE with sceneSDF
        result.steps++;
        if (d < hitEps) {
            result.hit = true; result.distance = t; return result;
        }
        t += max(d * omega, 0.001);
    }
    return result;
}
```

Cost: ~30–50% fewer steps on average than basic sphere tracing in open scenes. Worth it at maxSteps = 64+.

### 7.5 Per-primitive material IDs

When a scene has multiple materials, encode material ID in the SDF return alongside distance. A common pattern is returning a `float2(distance, material_id)`. The G-buffer pass then dispatches to the right `mat_*` recipe per hit.

```metal
float2 scene_sdf_with_material(float3 p) {
    float2 result = float2(1e10, -1.0);
    // Primitive 1: silk threads (material ID 1)
    float d1 = sd_silk_threads(p);
    if (d1 < result.x) result = float2(d1, 1.0);
    // Primitive 2: spider body (material ID 2)
    float d2 = sd_spider(p);
    if (d2 < result.x) result = float2(d2, 2.0);
    // Primitive 3: background sphere (material ID 0)
    float d3 = sd_bg_sphere(p);
    if (d3 < result.x) result = float2(d3, 0.0);
    return result;
}
```

Preset-authored `sceneMaterial()` dispatches on material_id to populate G-buffer.

---

## 8. Texturing Beyond Noise

### 8.1 Triplanar projection

The single highest-leverage non-noise technique. Projects textures along three world-axis planes and blends by normal alignment. Avoids the UV-mapping problem entirely on procedural geometry.

```metal
float3 triplanar_sample(texture2d<float> tex, sampler s, float3 wp, float3 n, float tiling) {
    float3 blend = pow(abs(n), float3(4.0));
    blend /= dot(blend, float3(1.0));
    float3 x = tex.sample(s, wp.yz * tiling).rgb;
    float3 y = tex.sample(s, wp.xz * tiling).rgb;
    float3 z = tex.sample(s, wp.xy * tiling).rgb;
    return x * blend.x + y * blend.y + z * blend.z;
}
```

Use everywhere you'd normally use 2D UVs on non-flat geometry: concrete walls, stone, bark, any extruded SDF.

### 8.2 Triplanar normal mapping with re-orientation

Naive triplanar of normal maps produces incorrect results — the tangent frame differs per axis plane. The fix uses Reoriented Normal Mapping (RNM): lifts tangent-space normals per-face into world space using each face's implicit tangent/bitangent basis.

```metal
// PBR/Triplanar.metal:triplanar_normal (Increment V.1)
static inline float3 triplanar_normal(
    texture2d<float> nmap, sampler samp,
    float3 wp, float3 n, float tiling
) {
    float3 w  = triplanar_blend_weights(n, 4.0);

    float3 nXZ = decode_normal_map(nmap.sample(samp, wp.xz * tiling).rgb);
    float3 nXY = decode_normal_map(nmap.sample(samp, wp.xy * tiling).rgb);
    float3 nYZ = decode_normal_map(nmap.sample(samp, wp.yz * tiling).rgb);

    // RNM: reorient each face's tangent-space normal to world space.
    // XZ face: tangent=+X, bitangent=+Z, normal=+Y
    float3 wsXZ = float3(nXZ.x, nXZ.z, nXZ.y + sign(n.y));
    // XY face: tangent=+X, bitangent=+Y, normal=+Z
    float3 wsXY = float3(nXY.x, nXY.y, nXY.z + sign(n.z));
    // YZ face: tangent=+Z, bitangent=+Y, normal=+X
    float3 wsYZ = float3(nYZ.z + sign(n.x), nYZ.y, nYZ.x);

    return normalize(wsXZ * w.y + wsXY * w.z + wsYZ * w.x);
}
```

**Procedural 3-param overload (no texture).** `Materials/MaterialResult.metal` provides `triplanar_normal(wp, n, amplitude)` and `triplanar_detail_normal(base_n, wp, amplitude)` that perturb a normal with fbm8 noise triplanarly — no texture required. Used by `mat_wet_stone`, `mat_bark`, `mat_granite`.

### 8.3 Parallax occlusion mapping (POM)

**Use for:** making concrete, bark, stone walls look like they have real depth rather than a normal map lie.

POM samples a heightmap along the view ray to find the correct surface displacement point. Expensive but the visual difference is dramatic.

`PBR/POM.metal` provides two forms. Basic POM returns the displaced UV only; the shadowed variant also returns a self-shadow factor for contact shadows inside deep features (reference: Morgan McGuire 2005).

```metal
// PBR/POM.metal (Increment V.1)

// Result type for the shadowed variant.
struct POMResult {
    float2 uv;          // displaced UV — use for all subsequent texture samples
    float  self_shadow; // [0,1] multiply into direct lighting; 0 = fully shadowed
};

// Basic POM: 32-step linear search + 8-step binary refinement.
// view_ts = view direction in tangent space (use ws_to_ts()).
// depth_scale: 0.02 = subtle brick mortar, 0.1 = deep rock.
static inline float2 parallax_occlusion(
    texture2d<float> height_tex, sampler samp,
    float2 uv, float3 view_ts, float depth_scale
) {
    const int linear_steps = 32;
    const int binary_steps = 8;
    float  layer_depth = 1.0 / float(linear_steps);
    float2 delta_uv    = (view_ts.xy / view_ts.z) * depth_scale / float(linear_steps);
    float  curr_depth  = 0.0;
    float2 curr_uv     = uv;
    float  curr_height = 1.0 - height_tex.sample(samp, curr_uv).r;
    for (int i = 0; i < linear_steps; i++) {
        if (curr_depth >= curr_height) break;
        curr_uv     -= delta_uv;
        curr_height  = 1.0 - height_tex.sample(samp, curr_uv).r;
        curr_depth  += layer_depth;
    }
    // Binary refinement between last two layers (Morgan McGuire 2005).
    float2 prev_uv    = curr_uv + delta_uv;
    float  prev_depth = curr_depth - layer_depth;
    for (int i = 0; i < binary_steps; i++) {
        float2 mid_uv    = (curr_uv + prev_uv) * 0.5;
        float  mid_depth = (curr_depth + prev_depth) * 0.5;
        float  mid_h     = 1.0 - height_tex.sample(samp, mid_uv).r;
        if (mid_depth >= mid_h) { curr_uv = mid_uv; curr_depth = mid_depth; }
        else                    { prev_uv = mid_uv; prev_depth = mid_depth; }
    }
    return (curr_uv + prev_uv) * 0.5;
}

// Shadowed variant — 2× more expensive; returns POMResult.
// light_ts = light direction in tangent space (use ws_to_ts() with the light dir).
static inline POMResult parallax_occlusion_shadowed(
    texture2d<float> height_tex, sampler samp,
    float2 uv, float3 view_ts, float3 light_ts, float depth_scale
);
```

Cost: ~1.0 ms per full-screen POM pass at 1080p on Tier 2 (basic), ~2.0 ms shadowed. Use sparingly on hero surfaces only.

### 8.4 Detail normals

Layer multiple normal-map scales: a macro normal map at base UV frequency, plus a detail normal at 20× UV frequency. `PBR/DetailNormals.metal` provides two blending modes:

```metal
// PBR/DetailNormals.metal (Increment V.1)

// UDN (Unity Detail Normal) blend — industry standard.
// Preserves detail scale without tilting the base normal.
// Both inputs are tangent-space normals (z-up convention).
static inline float3 combine_normals_udn(float3 base, float3 detail) {
    return normalize(float3(base.xy + detail.xy, base.z));
}

// Whiteout blend — more accurate when the base normal is itself steeply tilted.
// ~5% more expensive than UDN.
static inline float3 combine_normals_whiteout(float3 base, float3 detail) {
    float3 n = float3(
        base.x * detail.z + detail.x * base.z,
        base.y * detail.z + detail.y * base.z,
        base.z * detail.z
    );
    return normalize(n);
}
```

Use UDN for almost all cases. Switch to whiteout only when the base normal is tilted >45° (unusual geometry, e.g., overhanging rock).

Use for: bark (bark grooves + fine texture), sand (dunes + grain), any weathered surface.

### 8.5 Flow maps

For liquid surfaces: encode 2D flow-velocity vectors in an RG texture (or derive them procedurally from curl noise). Offset UVs per frame by the velocity. Two-phase mixing hides the repeating cycle. `Texture/FlowMaps.metal` decomposes this into composable helpers:

```metal
// Texture/FlowMaps.metal (Increment V.2)

// Compute distorted UV at animation phase [0,1].
// velocity  = flow direction + speed (decode from RG texture: vel = sample.rg*2-1)
// phase     = fract(time / period)  — caller controls cycle rate
// strength  = displacement amplitude (0.05–0.15 typical)
static inline float2 flow_sample_offset(float2 uv, float2 velocity, float phase, float strength) {
    return uv + velocity * (phase - 0.5) * strength;
}

// Smooth blend weight for dual-phase sampling (crossfades at phase 0 and 0.5).
// Weight for phase B = 1.0 - flow_blend_weight(phase).
static inline float flow_blend_weight(float phase) {
    return 1.0 - smoothstep(0.4, 0.6, fract(phase));
}

// Typical usage (texture-based):
//   float2 vel  = flowTex.sample(s, uv).rg * 2.0 - 1.0;
//   float  ph   = fract(time * 0.5);
//   float2 uv0  = flow_sample_offset(uv, vel, ph,       strength);
//   float2 uv1  = flow_sample_offset(uv, vel, ph + 0.5, strength);
//   float  w    = flow_blend_weight(ph);
//   float3 col  = baseTex.sample(s, uv0).rgb * w + baseTex.sample(s, uv1).rgb * (1.0 - w);

// Procedural alternative (no texture needed):
//   float2 vel = flow_noise_velocity(uv, scale, t);   // gradient of perlin3d
//   float2 vel = flow_curl_velocity(uv, scale, t);    // 2D curl of perlin3d
//   float2 distortedUV = flow_curl_advect(uv, scale, t, dt, strength);
```

Use for: ocean surface flow, ink-style presets, lava, any surface with directional streaming motion. The procedural variants (`flow_curl_advect`, `flow_noise_velocity`) need no texture and cost ~2 perlin samples each.

---

## 9. Performance Guidance

### 9.1 Frame budget anchors

Target: 16.6 ms per frame (60 fps). Breakdown on M3 Pro (Tier 2) at 1080p:

| Pass | Typical cost | Budget fraction |
|---|---|---|
| Ray march G-buffer (64 steps, 3 materials) | 2.5–4.0 ms | 15–24% |
| PBR lighting + IBL | 1.0–1.5 ms | 6–9% |
| SSGI (8-sample spiral, half-res) | 0.8–1.2 ms | 5–7% |
| Post-process (bloom + ACES) | 1.0 ms | 6% |
| `mv_warp` (3-pass) | 0.6 ms | 4% |
| Stem separation (MPSGraph, every 5 s) | 142 ms amortized | 1.4% averaged |
| MIR pipeline | <0.5 ms CPU | trivial |
| Swift render-loop overhead | 1.0 ms | 6% |
| **Ceiling for preset-specific work** | **~7 ms** | **~40%** |

The 7 ms ceiling is where preset fidelity ambition plays out. Big techniques cost real percent of this:

- POM full-screen: 1.0 ms (14% of ceiling)
- Volumetric light shafts: 1.5 ms (21% of ceiling)
- Volumetric clouds full-quality: 3.0 ms (43% of ceiling)
- Triplanar sampling: ~0.3 ms per surface type
- 8-octave fBM per-pixel: 0.8 ms per full-screen usage

### 9.2 Budgeting strategies

**Budget within `sceneMaterial()` not `sceneSDF()`.** Material calculations run once per ray hit; SDF evaluations run many times per ray. A heavy `sceneMaterial` with multiple noise calls and triplanar samples is fine; the same work inside `sceneSDF` compounds.

**Sample noise once, reuse.** Computing `fbm8(p)` three times inside the same shader is waste. Compute once into a variable.

**Prefer half-res for SSGI / volumetric / caustics.** MetalFX Temporal upscale handles reconstruction (Increment 3.16 planned).

**Avoid dynamic loops with variable iteration counts.** GPU divergence is expensive. Fixed loop counts with early-exit (`break` on convergence) compile well.

**Amortize across frames for slowly-changing terms.** SSGI, long-range AO, IBL pre-filtering — temporal accumulation with blue-noise jitter.

### 9.3 Tier 1 vs Tier 2 differentiation

Every preset should specify `complexity_cost: {"tier1": X, "tier2": Y}` in its JSON sidecar. Orchestrator excludes presets whose tier cost exceeds frame budget. From `CLAUDE.md`:

- Tier 1 (M1/M2): stricter ceilings. 5 ms per preset max. No volumetric clouds. No full-screen POM. Simplified mesh shader fallbacks.
- Tier 2 (M3+): full ambition. 7 ms per preset max. All techniques available. MetalFX Temporal Upscaling can rescue 25% of budget.

The `FrameBudgetManager` (Increment 6.2) downshifts at runtime when measured frames exceed budget — disables SSGI, reduces ray march steps, reduces particle count. Design presets to degrade gracefully under these reductions.

### 9.4 Cost of specific recipes (reference table)

Two-column table: Tier 1 (M1/M2) estimated via ~2.3× ratio from Tier 2 measurements; Tier 2 (M3+) measured via GPU timestamps at 1080p. Run `PERF_TESTS=1 swift test --filter UtilityPerformanceTests` and then `swift run UtilityCostTableUpdater` to regenerate.

<!-- BEGIN V4 PERF TABLE -->
_Initial estimates — run UtilityPerformanceTests with PERF_TESTS=1 to measure (generated 2026-04-26)_

| Function | Category | Tier 1 (estimated) | Tier 2 (estimated) | Notes |
|---|---|---|---|---|
| `palette` | color | ~0.03 ms [estimated] | ~0.015 ms [estimated] | IQ cosine palette (4-param) |
| `tone_map_aces` | color | ~0.06 ms [estimated] | ~0.025 ms [estimated] | ACES tone mapping (filmic) |
| `chromatic_aberration_radial` | color | ~0.07 ms [estimated] | ~0.030 ms [estimated] | Chromatic aberration (radial) |
| `ray_march_adaptive` | geometry | ~5.75 ms [estimated] | ~2.5 ms [estimated] | Adaptive sphere tracer, 64 steps max |
| `sd_mandelbulb_iterate` | geometry | ~0.80 ms [estimated] | ~0.35 ms [estimated] | Mandelbulb iterate, n=8, 6 iters |
| `hex_tile_uv` | geometry | ~0.09 ms [estimated] | ~0.04 ms [estimated] | Hex tile UV (Mikkelsen, no textures) |
| `mat_polished_chrome` | materials | ~1.89 ms [estimated] | ~0.82 ms [estimated] | Polished chrome (fbm8 streak) |
| `mat_marble` | materials | ~4.03 ms [estimated] | ~1.75 ms [estimated] | Marble (curl_noise + fbm8 veins) |
| `mat_granite` | materials | ~4.37 ms [estimated] | ~1.90 ms [estimated] | Granite (worley_fbm + fbm8 + triplanar) |
| `mat_ocean` | materials | ~5.98 ms [estimated] | ~2.60 ms [estimated] | Ocean water (fbm8 capillary ripple) |
| `fbm8` | noise | ~1.84 ms [estimated] | ~0.80 ms [estimated] | 8-octave fBM, 3D, full-screen 1080p |
| `fbm4` | noise | ~0.97 ms [estimated] | ~0.42 ms [estimated] | 4-octave fBM, 3D, full-screen 1080p |
| `curl_noise` | noise | ~2.19 ms [estimated] | ~0.95 ms [estimated] | 3D curl noise (6 fbm8 samples) |
| `worley_fbm` | noise | ~1.50 ms [estimated] | ~0.65 ms [estimated] | Worley-Perlin blend, 3D |
| `brdf_ggx` | pbr | ~0.41 ms [estimated] | ~0.18 ms [estimated] | Full Cook-Torrance GGX BRDF |
| `sss_backlit` | pbr | ~0.21 ms [estimated] | ~0.09 ms [estimated] | SSS back-lit approximation |
| `thinfilm_rgb` | pbr | ~0.28 ms [estimated] | ~0.12 ms [estimated] | Thin-film interference RGB |
| `grunge_composite` | texture | ~1.61 ms [estimated] | ~0.70 ms [estimated] | Composite grunge (scratches+rust+wear) |
| `rd_pattern_animated` | texture | ~0.46 ms [estimated] | ~0.20 ms [estimated] | Reaction-diffusion animated approx |
| `voronoi_cracks` | texture | ~0.30 ms [estimated] | ~0.13 ms [estimated] | Voronoi crack distance field |
| `voronoi_f1f2` | texture | ~0.25 ms [estimated] | ~0.11 ms [estimated] | 2D Voronoi F1+F2, 9-cell search |
| `cloud_density_cumulus` | volume | ~1.04 ms [estimated] | ~0.45 ms [estimated] | Cumulus cloud density field |
| `hg_phase` | volume | ~0.05 ms [estimated] | ~0.02 ms [estimated] | Henyey-Greenstein phase function |
| `vol_density_fbm` | volume | ~0.69 ms [estimated] | ~0.30 ms [estimated] | Volume density fBM, 3 octaves |
<!-- END V4 PERF TABLE -->

**Surprises (V.4 calibration notes):**
- `mat_granite` is the heaviest cookbook material at ~1.9 ms — three noise calls at different scales + triplanar. Use per-hit, not per-pixel.
- `mat_ocean` approaches the ray-march G-buffer budget at ~2.6 ms. Combine with reduced raymarch steps (64→48) when using mat_ocean.
- `curl_noise` costs 6× `fbm8` (it's 6 finite-difference fbm8 samples) — always call once per hit point, never per-pixel in isolation.
- `warped_fbm` (7× fbm8) is not in the benchmark table; estimated ~5.5 ms — use only on hero geometry, never full-screen.
- `hex_tile_uv` is essentially free (~0.04 ms) and should be used liberally for any surface needing repeating patterns without UV seams.

For primitives not in this table, estimate ~0.04 ms per `perlin3d` call and scale by octave count.

### 9.5 Profiling every new preset

Before a new preset is certified: run `swift test --filter PresetPerformanceTests` with synthetic 60-second captures on silence, steady mid-energy, and beat-heavy fixtures from `Increment 5.2`. Record p50 / p95 / p99 / max frame time. Any p95 > tier budget is a fail.

---

## 10. Per-Preset Fidelity Playbook

Concrete uplift recipes for the five presets Matt called out. Each references sections above.

### 10.1 Arachne (V.8 — see `docs/presets/ARACHNE_V8_DESIGN.md`)

**This section is superseded by `docs/presets/ARACHNE_V8_DESIGN.md` (2026-05-02).** The compositing-anchored sketch below was a partial design that didn't yet incorporate Matt's design conversation about (a) the construction-sequence-as-subject reframing prompted by the BBC Earth time-lapse references and (b) the orchestrator-side change to support multi-segment-per-track preset transitions on preset-declared cadences. The full v8 design lives in the dedicated doc.

The sketch below is preserved only for context — it documents the architectural pivot from V.7.5 (constant-tweaking) to compositing layers. The implementation plan in `ARACHNE_V8_DESIGN.md` §6 supersedes the V.7.7-V.7.9 sequence below.

---

#### 10.1 (legacy sketch) Arachne (V.7.7+ — compositing-anchored, post-V.7.5 pivot)

**Hero reference:** `01_macro_dewy_web_on_dark.jpg`. If a session matches one frame, match this one. **Anti-references:** `09_anti_clipart_symmetry.jpg` (failure mode #1: clipart) and `10_anti_neon_stylized_glow.jpg` (failure mode #2: graphic-glow). The V.7.5 build still reads as a stylized 2D bullseye visually distant from the references — not because individual constants are wrong, but because the renderer is missing entire compositing layers the references depend on. (Background: D-072, M7 session `2026-05-02T01-35-34Z`.)

**Target:** nature-documentary close-up of a dewy orb-weaver web. Drops carry the visual; threads are faint connective tissue between drop chains. The world the web sits in is half the visual: atmospheric backlit haze, defocused foliage, beams of light through dust. Each drop is a tiny refractive lens distorting and inverting the background behind it (refs `03`, `04`). Pure black is the silence-calibration state only (per `08_palette_bioluminescent_organism.jpg`), not the steady-playback state.

**Architecture mandate (D-072):** This rewrite is compositional, not parametric. The V.7.5 constant-tuning pass is preserved as the v5 baseline (silk × 0.32, drop radius 0.008 UV, sag range [0.06, 0.14], pool cap 4, warm key + cool ambient, dark spider silhouette, AR gate restored, subBassThreshold 0.30) — every V.7.5 commit stays in the tree. V.7.7/V.7.8/V.7.9 add three new compositing layers around that baseline. The pre-pivot V.7.6 (atmosphere as a multiplicative-mist patch) is abandoned; that scope moves into V.7.7 with the right architectural shape. D-043's 2D SDF mandate stands.

**The reference visual signature decomposes into three layers:**

1. **A textured atmospheric world behind the web** — defocused foliage, warm-to-cool aerial perspective, optional volumetric backlight beam. Refs `01`, `03`, `04`, `05`, `06`, `07` all show this; current preset has none.
2. **Drops as refractive lenses, not glowing dots** — refs `03` and `04` show drops as spherical-cap lenses inverting the background through refraction. The "real water" optical signature is refraction + fresnel rim + sharp specular pinpoint, not emissive amber.
3. **Optical depth via DoF and chord-segment threads** — refs `01`, `03` show heavy bokeh blur falling off into the distance. Refs `04`, `08` show threads as discrete straight chord segments between attachment points, not smooth Archimedean curves. The renderer needs depth-aware blur and a chord-segment SDF replacement.

#### 10.1.A Background atmosphere pass (V.7.7)

**Per** `01_macro_dewy_web_on_dark.jpg`, `03_micro_adhesive_droplet.jpg`, `04_specular_silk_fiber_highlight.jpg`, `05_lighting_backlit_atmosphere.jpg`, `06_atmosphere_dark_misty_forest.jpg`, `07_atmosphere_dust_light_shaft.jpg`.

Render an offscreen background texture before the web pass. Compose under the web. Output is sampled by the drops (V.8.2) for refraction. Layers:

- **Mood-tinted vertical aerial-perspective gradient** — warm amber-bottom for high-valence states (ref `04` golden glow, ref `05` golden field), cool blue-grey for low-valence (ref `06` cool palette). `mix(bottomColor, topColor, saturate(uv.y * 1.2 - 0.1))` with both colors driven by valence + arousal. Pure black at silence is the explicit calibration anchor (ref `08`), not a steady-state default.
- **Defocused foliage** via `worley_fbm` at low frequency (≈ 2–4 in UV space) writing dim silhouettes into the gradient. Mottled with `fbm8` at lower amplitude for organic variation. Heavily desaturated and darkened so it reads as "out-of-focus background", not a competing subject. Apply baked-in mild Gaussian blur (3–5 px) so foliage edges are soft.
- **Optional volumetric beam** — when `f.mid_att_rel > 0.05`, render a soft directional beam from `kL` projected to UV space: additive warm tint along the beam axis with perpendicular falloff via `smoothstep(beamHalfWidth, 0, perpDist)`. Replaces the V.7-era isotropic mote field with the beam structure ref `07` actually shows.
- **Vignette** — radial darkening at the frame edges so the eye is drawn to the centered hero composition. Subtle (≈ 30 % attenuation at corners).

The bg pass is a separate render-to-texture call before `arachne_fragment`. Texture binding: a new `arachneBackgroundTexture` at fragment texture index 12 (next available after IBL slots). Resolution: half-res (`drawableSize / 2`) is fine — it's defocused anyway, and we save bandwidth. Lifetime: regenerated per frame so audio modulation lands continuously.

#### 10.1.B Drops as refractive lenses (V.7.8)

**Per** `03_micro_adhesive_droplet.jpg`, `04_specular_silk_fiber_highlight.jpg`, `01_macro_dewy_web_on_dark.jpg`.

The current drop block (V.7.5: warm-amber emissive × 0.18 + warm specular pinpoint) is replaced with a refractive-glass recipe that samples the background texture from V.8.1.

Inside the existing drop loop, where we already compute `detail_normal` (the spherical-cap normal):

```
// Refract the bg texture through the drop. Snell's law: eta = 1/IOR_water ≈ 1/1.33 ≈ 0.752.
// The cap normal points away from the water; refraction bends the view ray INTO the drop,
// producing the inverted, magnified image of the bg that refs 03/04 show.
float3 viewDir = float3(0, 0, -1);  // screen-space view
float3 refractDir = refract(viewDir, detail_normal, 0.752);
float2 refractUV = uv + refractDir.xy * dropRadius * 1.5;  // scale tuned to ref 04 magnification
float3 bgRefracted = bgTex.sample(bgSampler, refractUV).rgb;

// Fresnel rim: edges of the drop have higher reflectance, dimmer refraction.
float fresnel = pow(1.0 - saturate(dot(detail_normal, -viewDir)), 5.0);
float3 dropColor = mix(bgRefracted, float3(0.0), fresnel * 0.7);  // dark fresnel rim ring

// Specular pinpoint: tiny mirror-like highlight from kL.
float3 R = reflect(-kL, detail_normal);
float spec = pow(saturate(dot(R, -viewDir)), 96.0);  // tighter than V.7.5 (was 64)
dropColor += float3(1.00, 0.95, 0.85) * spec * 2.0;  // brighter pinpoint to read against bg

// Edge ring: dark thin ring at the drop perimeter for crisp definition.
float edgeRing = smoothstep(dropRadius - 0.001, dropRadius - 0.0005, length(d2));
dropColor *= mix(1.0, 0.4, edgeRing);
```

**Density and visual hierarchy inversion.** Bump drop spacing tighter (3–5 px instead of 4–6 px from V.7.5) so chains visibly bead-touch as in ref `01`. Drops are no longer audio-gain-modulated via emissive multiplier (the bg is what's bright now, drops show whatever the bg is doing); audio modulation moves to the bg pass intensity (warm-key beam strength scales with `f.bass_att_rel`).

**Strand emission falls further.** With drops doing the visual work, silk strands drop from V.7.5's `silkTint × 0.32` to `silkTint × 0.18` for the anchor web, `× 0.12 × w.opacity` for pool webs. They become the faint connective tissue between drop chains the references show.

#### 10.1.C Chord-segment spiral + selective DoF (V.7.9)

**Per** `04_specular_silk_fiber_highlight.jpg`, `08_palette_bioluminescent_organism.jpg`, `01_macro_dewy_web_on_dark.jpg`.

**Chord-segment spiral.** Replace the continuous Archimedean spiral SDF (`arachneEvalWeb` lines computing `theta - (rT/webR)*spirRevs*2π` then `min(fract, 1-fract)`) with discrete chord segments. For each spiral revolution N, for each pair of adjacent radials at angles θᵢ and θᵢ₊₁, place one straight line segment between the radial-attachment points at radius `r(N, θᵢ) = (N + θᵢ/(2π)) × webR / spirRevs`. Compute distance via per-segment `arachSegDist`. Visually breaks the bullseye effect because the spiral now reads as a sequence of straight chords (which is what real spiders weave) rather than a continuous curve that degenerates to rings at narrow line thickness.

Cost: `O(spokeCount × spirRevs)` segment distance evals per pixel, gated by an early-exit on radial distance to web center. At spokeCount=11–17 and spirRevs=4–8, that's 44–136 segment evals per pixel inside the web hit-box — acceptable on Tier 2; gated to Tier 1 by reducing `spirRevs` to 4.

**Selective depth-of-field.** Add a depth-weighted bokeh pass to `PostProcessChain`. Each web carries an existing `depth ∈ [0, 1]` field (already in `WebGPU` struct). Foreground anchor web (depth ≈ 0) renders sharp; pool webs at higher depth values get progressively more circular-aperture blur applied via a 9-tap disc-kernel sample in screen space. Drops on near webs stay sharp (the hero detail); distant drops blur into bokeh circles (matches refs `01`, `03`). Use the existing `noiseFBM` texture for blue-noise dither so the bokeh doesn't band.

The DoF pass runs after the web pass and before `mv_warp`. Reuses `PostProcessChain.bloomEnabled` infrastructure pattern but adds a third pipeline state for the bokeh kernel.

#### 10.1.D Audio reactivity (unchanged from V.7.5 — do NOT relitigate)

D-026 deviation primitives. Continuous: `f.bass_att_rel` (now drives bg-pass beam intensity instead of strand emissive gain). Beat accent: `0.07 * max(0, stems.drums_energy_dev)` (now subtle additive on bg warmth, since drops are no longer emissive). `f.mid_att_rel` drives bg foliage/beam contrast. Geometry static per D-020. Continuous/beat ratio ≥ 2× per CLAUDE.md rule of thumb. AR gate + sub-bass threshold for spider unchanged from V.7.5.

#### 10.1.E Spider (unchanged from V.7.5 — do NOT relitigate)

Dark silhouette `(0.04, 0.03, 0.02)` with thin warm-amber rim catching backlit `kL`. AR gate + threshold tuned per V.7.5 §10.1.9. The spider is still composited on top of the web on top of the bg.

**Budget:** ≤ 6.0 ms p95 at 1080p Tier 2 (raised from 5.5 ms to budget for the bg pass + DoF kernel). Tier 1 budget allows 7.5 ms.

**Sessions estimated:** 3 — V.7.7 covers §10.1.A (background pass). V.7.8 covers §10.1.B (refractive drops + visual hierarchy inversion). V.7.9 covers §10.1.C (chord-segment spiral + DoF) plus the cert-review eyeball. The pre-pivot V.7.6 plan (atmosphere as a multiplicative-mist patch on the existing single-pass renderer) is **abandoned** per D-072 — the bg pass in V.7.7 is the proper home for atmosphere. V.8 remains reserved for Gossamer per §10.2.

**M7 prep (mandatory final step of every V.7+ session per D-071):** Capture a single representative frame at steady mid-energy. Place it in a 2×4 contact sheet with `01`, `02`, `03`, `04`, `05`, `07`, `08`, `10`. Record pass/fail per positive reference and a "matches anti-ref?" boolean for `10`. The session is not done if the anti-ref boolean is true on `10`, regardless of automated rubric score.

### 10.2 Gossamer (V.8)

**Current state:** static SDF web with colored propagating waves. Waves are pure palette shifts, no displacement.

**Target:** singular hero web that physically resonates with sound. Waves visibly displace silk threads. Silk glows with vocal pitch color. Chromatic aberration on wave peaks.

**Uplift plan:**

1. **Macro:** 17 explicit irregular spoke angles (already in v3), off-center hub. Raise thread count on spiral (more turns, finer thread) to make the web read as an instrument not a geometry study.
2. **Meso:** physical wave displacement. Each active wave at vocal-pitch-keyed color actually offsets the silk strand position in the direction perpendicular to strand tangent, amplitude scaled by wave amplitude. Requires per-strand SDF evaluation, not uniform displacement.
3. **Micro:** silk thread material per §4.3. Same Marschner-lite as Arachne but tuned `azimuthal_r = 0.08, azimuthal_tt = 0.5, absorption = 0.3`.
4. **Specular:** fine specular glints at node intersections where strands cross. Chromatic aberration on strongest waves: RGB channels sampled at slightly offset positions for a prismatic highlight.
5. **Atmosphere:** bioluminescent ambient haze in a 0.5-radius halo around the web. Dust motes drawn inward by wave energy, outward at silence.
6. **Lighting:** scene is nearly-black. Web emission is the primary light source. SSGI picks up web emission and projects soft ambient fill onto background — very visible in a dark scene.
7. **Audio reactivity:** waves are vocal-pitch-keyed (current), but velocity of wave propagation becomes `2.0 + stems.vocals_energy_dev * 5.0` (faster waves on high vocal energy). Wave amplitude drives displacement magnitude per §10.2.2. Dust-mote inward drift velocity from `stems.vocals_energy_att`.

**Budget:** ~4.5 ms on Tier 2.

**Sessions estimated:** 2 (physical displacement rework / atmosphere + chromatic aberration).

### 10.3 Ferrofluid Ocean (V.9)

**Current state:** HDR post-process chain over simple surface. Not iconic.

**Target:** living magnetic-fluid surface under audio-driven magnetic field. Rosensweig spike lattice. Pitch-black with razor-sharp reflective highlights. Background sky entirely mirrored in fluid surface.

**Uplift plan:**

1. **Macro:** replace current surface with ferrofluid field per §4.6. Hex-tile spike lattice, spike height driven by `stems.bass_energy_dev`.
2. **Meso:** domain-warp the spike-center positions per §3.4 so hexagonal symmetry is broken by organic flow. Flow velocity driven by `stems.drums_beat` rising edges.
3. **Micro:** surface-scale detail noise on each spike (fbm8 at 15× scale, normal perturbation amplitude 0.02). Micro-droplets at spike tips on high amplitude — hash-lattice distributed.
4. **Specular:** ferrofluid material per §4.6. Anisotropic reflection aligned with spike axes.
5. **Atmosphere:** distant fog cools to dark purple. Sky dome above (IBL cubemap) is the primary indirect light — every polished spike reflects a tiny piece of the sky.
6. **Lighting:** minimal direct lighting. Strong IBL cubemap. One warm key light far off to give spike-tip highlights a direction. Caustic underlighting from below surface (faint cyan) suggests depth.
7. **Audio reactivity:** bass drives spike height (Rosensweig field strength). Drums drive beat-surface ripple. Vocals drive surface tension (spike sharpness — lower tension = blunter spikes). "Other" drives rotational flow direction.

**Budget:** ~6.0 ms on Tier 2.

**Sessions estimated:** 4 (field formulation / material / lighting + IBL / audio routing).

### 10.4 Fractal Tree (V.10)

**Current state:** mesh-shader procedural L-system geometry. Bare branches, no bark, no foliage, no wind.

**Target:** painterly tree in seasonal palette, bark with real displacement, translucent leaves, wind-driven motion.

**Uplift plan:**

1. **Macro:** L-system tree generation stays. Increase branching depth by 1 level on Tier 2 for visual density.
2. **Meso:** bark displacement via POM per §8.3 using a generated heightmap (procedural from `ridged_mf`). Branch thickness varies per segment via `fbm8` rather than strict L-system prescription.
3. **Micro:** bark material per §4.7 — lichen patches, vertical fiber ridges, triplanar detail normal.
4. **Specular:** roughness variation along bark via `fbm8`. Wet-bark mode (controllable by JSON) for rain-slick appearance.
5. **Atmosphere:** ground fog at low altitude. Aerial perspective on distant branches (color desaturation with depth).
6. **Lighting:** golden-hour per §5.6. Leaves receive strong back-lit SSS from key light. Shadows cast between branches via shadow-map sampling.
7. **Foliage:** NEW — add procedural leaf clusters at branch tips. Each cluster is a billboarded quad with leaf material (§4.8). 200–500 leaves per tree on Tier 2.
8. **Wind animation:** per-branch offset driven by `curl_noise(wp + time)`. Leaves sway more than branches (greater amplitude at higher L-system depth). Tie gust intensity to `stems.other_energy_att`.
9. **Seasonal palette:** JSON toggle among `spring` (green + pink blossoms), `summer` (deep green), `autumn` (orange/red), `winter` (bare + frost). Default autumn. Sync with valence: negative valence → winter, positive → spring/summer.

**Budget:** ~6.5 ms on Tier 2 (POM on bark + many leaves).

**Sessions estimated:** 4 (bark material + POM / foliage / wind animation / seasonal palette + audio routing).

### 10.5 Volumetric Lithograph (V.11)

**Current state:** fBM heightfield terrain, bimodal materials, IQ cosine palette. Has been iterated 6+ times. Lacks topographic conviction — reads as lumpy rather than mountainous.

**Target:** mountainous landscape with aerial perspective and drifting cloud shadows. Linocut aesthetic but with real depth.

**Uplift plan:**

1. **Macro:** replace current fBM heightfield with `ridged_mf` per §3.3 warped by `curl_noise` for drainage flow. Terrain reads as eroded mountainous range, not lumps.
2. **Meso:** secondary displacement layer adds mesa terraces via `step(frac(h * 8.0), 0.5) * 0.05`. Optional — selectable per-variant for geological theme.
3. **Micro:** triplanar detail normal per §8.2 at 30× scale. Kills stretched texels on steep faces.
4. **Specular:** keep current bimodal peak/valley materials. Add specular variation via second fBM — prevents metallic peaks from reading as uniform chrome.
5. **Atmosphere:** NEW — aerial perspective fog. Color-shift fog `lerp(warm_sky, cool_depth, depth_factor)`. Distant peaks desaturate and brighten toward sky color. This single addition would transform the preset.
6. **Lighting:** keep current single-directional + IBL. Raise IBL contribution on distant geometry via screen-space AO falloff. Add long shadows via shadow-map or simple dot-ratio term for pseudo-occlusion.
7. **Clouds (optional):** drifting cloud shadows cast onto terrain via screen-space density sample. Low-cost — sample `fbm8(wp.xz + time * 0.02)` as scalar multiplier on key light intensity.
8. **Beat reactive:** replace palette flash on beat with "cutting-plane reveal" — a plane sweeps across the terrain from one direction, momentarily rendering crossed regions in inverted palette. Reads as "ink printing" motion.
9. **Audio reactivity:** terrain scrolls audio-time-swept per current. Add pitch-color modulation per current MV-3c. Add beat cutting-plane reveal per §10.5.8.

**Budget:** ~5.0 ms on Tier 2.

**Sessions estimated:** 3 (terrain reformulation with ridged_mf + curl warp / aerial perspective + clouds / cutting-plane beat + audio polish).

---

## 11. Infrastructure Changes

### 11.1 SwiftLint `file_length` exception for `.metal`

Current rule: 400 lines. Good shaders run 800–2000. `.swiftlint.yml` gets a path-based exception:

```yaml
included:
  - PhospheneEngine/Sources
excluded:
  - "**/Shaders/**/*.metal"

# Alternative: keep lint but raise threshold for .metal
file_length:
  warning: 400
  error: 1000
  ignore_comment_only_lines: true
```

(Exact mechanism depends on SwiftLint's support for per-glob config — may require a separate `.swiftlint-metal.yml` run on `.metal` files only. To be decided in Increment V.1 implementation.)

### 11.2 Utility library directory tree

From the improvement plan Increment V.1–V.3:

```
PhospheneEngine/Sources/Renderer/Shaders/Utilities/
  Noise/
    Perlin.metal         (~200 lines)
    Worley.metal         (~200 lines)
    Simplex.metal        (~150 lines)
    FBM.metal            (~250 lines — fbm4, fbm8, fbm12, vector fbm)
    RidgedMultifractal.metal  (~100 lines)
    DomainWarp.metal     (~200 lines)
    Curl.metal           (~120 lines)
    BlueNoise.metal      (~80 lines — IGN sampling helpers)
    Hash.metal           (~150 lines — various hash functions)
  PBR/
    BRDF.metal           (~300 lines — GGX, Lambert, Oren-Nayar, Ashikhmin-Shirley)
    Fresnel.metal        (~80 lines)
    NormalMapping.metal  (~150 lines)
    POM.metal            (~200 lines)
    Triplanar.metal      (~200 lines)
    DetailNormals.metal  (~100 lines)
    SSS.metal            (~150 lines)
    Fiber.metal          (~300 lines — Marschner-lite)
    Thin.metal           (~150 lines — thin-film interference)
  Geometry/
    SDFPrimitives.metal  (~400 lines — ~30 primitives)
    SDFBoolean.metal     (~200 lines — unions, intersections, smooth variants)
    SDFModifiers.metal   (~200 lines — repeat, mirror, twist, bend, scale)
    SDFDisplacement.metal (~150 lines)
    RayMarch.metal       (~200 lines — marching, normals, shadows)
    HexTile.metal        (~100 lines)
  Volume/
    ParticipatingMedia.metal  (~250 lines)
    HenyeyGreenstein.metal    (~60 lines)
    LightShafts.metal    (~200 lines)
    Caustics.metal       (~150 lines)
    Clouds.metal         (~300 lines)
  Texture/
    Voronoi.metal        (~200 lines)
    ReactionDiffusion.metal (~200 lines)
    FlowMaps.metal       (~150 lines)
    Procedural.metal     (~400 lines — wood, marble, grunge, rings)
    Grunge.metal         (~200 lines)
  Color/
    Palettes.metal       (~200 lines — IQ cosine, gradients, LUTs)
    ColorSpaces.metal    (~150 lines — RGB↔HSV↔Lab↔Oklab)
    ChromaticAberration.metal (~100 lines)
    ToneMapping.metal    (~150 lines — ACES, Reinhard variants, filmic)
```

Total: ~6800 lines across 35 files, averaging ~195 lines each.

`PresetLoader+Preamble.swift` is extended to include the full `Utilities/` tree before preset code — every preset gets these for free.

### 11.3 Material cookbook as a Metal header

Each material recipe from §4 ships as a function in `Shaders/Utilities/Materials/`:

```
Materials/
  Metals.metal       → mat_polished_chrome, mat_brushed_aluminum, mat_gold, mat_copper, mat_ferrofluid
  Dielectrics.metal  → mat_ceramic, mat_frosted_glass, mat_wet_stone
  Organic.metal      → mat_bark, mat_leaf, mat_silk_thread, mat_chitin
  Exotic.metal       → mat_ocean, mat_ink, mat_marble, mat_granite
```

Presets compose these by calling material functions directly from `sceneMaterial()`.

---

## 12. The Fidelity Rubric

Every preset must pass this rubric before certification (Increment V.6). Replaces the weak invariants in Increment 5.2.

### 12.1 Mandatory (fail any → not certified)

- [ ] **Detail cascade present.** All four scales (macro / meso / micro / specular breakup) implemented on every primary surface.
- [ ] **Minimum 4 noise octaves.** Somewhere in the shader. Single-octave-fBM presets fail.
- [ ] **Minimum 3 distinct materials.** Constant-material presets fail. Plasma-family presets exempt (explicitly stylized).
- [ ] **Audio-responsive through deviation primitives.** Uses `f.bass_rel/dev`, `f.mid_rel/dev`, etc. per D-026. Absolute-threshold presets fail.
- [ ] **Graceful silence fallback.** Non-black and non-static at `totalStemEnergy == 0`.
- [ ] **Performance within tier budget.** p95 frame time ≤ tier budget at 1080p.
- [ ] **Matt-approved reference frame match.** Visual regression compared against Matt-annotated reference images; Matt signs off.

### 12.2 Expected (≥ 2 of 4)

- [ ] Triplanar texturing on all non-planar surfaces
- [ ] Detail normals
- [ ] Volumetric fog or aerial perspective
- [ ] Subsurface scattering, fiber BRDF, or anisotropic specular on at least one material

### 12.3 Strongly preferred (≥ 1 of 4)

- [ ] Hero specular highlight visible in ≥60% of frames
- [ ] Parallax occlusion mapping on at least one surface
- [ ] Volumetric light shafts or dust motes
- [ ] Chromatic aberration or thin-film interference on at least one material

### 12.4 Rubric score

- Mandatory 7/7 required.
- Expected ≥ 2/4 required.
- Strongly preferred ≥ 1/4 required.

Minimum score: **10/15** with all mandatory items. Falling short on any mandatory = not certified regardless of optional score.

Uncertified presets exist in the catalog but the Orchestrator excludes them from session planning by default. A "show uncertified presets" toggle in `SettingsView` exists for testing but is off by default.

### 12.5 Certification pipeline (Increment V.6)

The rubric is enforced by `DefaultFidelityRubric` in `Sources/Presets/Certification/FidelityRubric.swift`. It evaluates each preset's Metal source and JSON sidecar statically and surfaces failures in `RubricResult`. `PresetCertificationStore` (actor) caches results for all production presets.

**To read the current rubric report for all presets:**

```bash
swift test --package-path PhospheneEngine --filter "FidelityRubricReportTests/rubricReport_allPresetsLoad" 2>&1 | grep -A 3 "\[✓\]\|\[✗\]"
```

**To certify a preset** after a fidelity uplift session:

1. Verify `meetsAutomatedGate == true` in the rubric report (Suite 1 output above).
2. Review the preset against `docs/VISUAL_REFERENCES/<preset>/README.md` reference images.
3. Set `"certified": true` in the preset's JSON sidecar.
4. Run `swift test --package-path PhospheneEngine --filter FidelityRubricTests` — Suite 2 gate dict must be updated (change `false → true` for the newly certified preset).

**Lightweight presets** (Plasma, Waveform, Nebula, SpectralCartograph) use a 4-item ladder (L1–L4) instead of the full 15. Add `"rubric_profile": "lightweight"` to the sidecar. Detail-cascade and material-count requirements are waived for stylized 2D / diagnostic presets. See D-067(b).

**`rubric_hints`** allows authors to assert P1 (hero specular) and P3 (dust motes) when the static analyzer cannot detect them from function names alone. Add `"rubric_hints": {"hero_specular": true, "dust_motes": false}` to the sidecar. The hints do not affect M1–M6 or the mandatory gate.

---

## 13. Failed Approaches (Shader-Specific)

Consolidated from observed preset iterations. Additive to `CLAUDE.md §Failed Approaches`.

**35. Single-octave noise for hero surfaces.** Every preset using 1–3 octaves of Perlin/fBM reads as primitive. Minimum 4 octaves. Minimum 8 octaves for hero geometry.

**36. Uniform-albedo-per-material presets.** Constant `float3 albedo` anywhere on a hero surface. Real surfaces have per-point variation. Drive albedo through `fbm8` or `worley_fbm` at minimum.

**37. Normal-map-only pretending to be displacement.** A flat surface with a fancy normal map looks flat from any grazing angle. If the surface should have real depth perception (concrete, bark, stone), use POM, not just normal mapping.

**38. Roughness constants.** `roughness = 0.3` reads as CGI-plastic. Vary roughness spatially via noise. Even 10% variation breaks the plastic look.

**39. Grey fog.** Fog color matching sky/horizon color is atmosphere. Grey fog is a printing defect. Always match fog to scene palette.

**40. Authoring without reference images.** Every preset iteration before Phase V was authored from prose description alone. Observed output: primitive. Reference-image-first authoring is mandatory per §2.3.

**41. Ray-march scene without any atmosphere.** A ray-march scene with fog disabled and no volumetric elements reads as "floating in void." Every ray-march preset should have at minimum exponential fog matched to palette.

**42. Cylinder-as-silk / cube-as-rock / sphere-as-organic.** SDF primitives are building blocks, not final forms. Always apply at least one modifier (displacement, twist, noise-driven deformation) before materials.

**43. Skipping `mv_warp` on static-camera direct-fragment presets.** Direct-fragment presets without temporal feedback show only instantaneous audio state. Motion feels mechanical. Add `mv_warp` unless D-029 camera-dolly / particle-system constraints apply.

**44. Mesh-shader presets without per-instance variation.** L-system fractals, particle swarms, procedural structures — if every instance is identical, the preset reads as clone-stamped. Per-instance hash-driven jitter is mandatory.

**45. Four-color palette presets with uniform saturation.** Saturation pushes to the eye as "cartoon." Real palettes have saturation variation (some near-white, some deep, some near-black). Use IQ cosine palette families with per-sample saturation modulation.

**46. Shader code written top-to-bottom without the coarse-to-fine pass structure.** Observed pattern: a single fragment shader tries to do everything. Observed result: debugging is impossible because all layers are interdependent. Pass structure per §2.2 makes each iteration targeted.

**47. Skipping mood-palette application at the IBL ambient level.** Per D-022, mood shifts must tint IBL ambient, not just direct light. Presets that tint only `lightColor.rgb` show mood changes only on direct-lit surfaces. Multiply IBL by `lightColor.rgb` so the shift propagates.

---

## 14. Authoring Cheat Sheet (for Session Prompts)

Condensed checklist for Claude Code sessions writing a new preset. Paste into session prompts.

```
SESSION CHECKLIST — before declaring complete:

[ ] Read docs/VISUAL_REFERENCES/<preset>/README.md and all reference images.
[ ] Listed four detail-cascade layers before writing code.
[ ] Coarse-to-fine implementation order (macro → meso → micro → specular →
    atmosphere → lighting → audio).
[ ] Minimum 4 octaves of noise in hero surface.
[ ] Minimum 3 distinct materials via cookbook recipes.
[ ] Triplanar projection on non-planar surfaces.
[ ] Atmosphere present (fog, aerial perspective, volumetric element).
[ ] Detail normals or POM on primary surface.
[ ] Audio reactivity via deviation primitives (f.*_rel, f.*_dev, stems.*_rel/dev).
[ ] Graceful silence fallback tested.
[ ] Performance measured against tier budget.
[ ] Hashed reference frame comparison passed.
[ ] Matt review requested.
```

---

## 15. Cross-References

- `CLAUDE.md §Audio Data Hierarchy` — the audio contract these shaders read
- `CLAUDE.md §GPU Contract Details` — buffer / texture binding layout (buffer 0 = FeatureVector, etc.)
- `CLAUDE.md §Preset Metadata Format` — JSON sidecar fields referenced here
- `CLAUDE.md §Failed Approaches` — shader failures 1–34; this doc extends with 35–47
- `MILKDROP_ARCHITECTURE.md §3d` — why `mv_warp` is critical for direct-fragment presets
- `DECISIONS.md D-019/D-020/D-022/D-026/D-027/D-029` — the accumulated wisdom that gates preset authoring
- `ENGINEERING_PLAN.md §Phase V` — the increments that implement this handbook
- `docs/VISUAL_REFERENCES/` — per-preset reference image library (Increment V.5)
- `UX_SPEC.md §7.4 Idle-visualizer floor` — the silent-state requirement this handbook enforces

---

## 16. Open Questions

Items to resolve during Phase V execution:

1. **SwiftLint per-glob config feasibility.** Does SwiftLint support path-based `file_length` overrides in a single `.swiftlint.yml`? If not, a second config file + script. To confirm in Increment V.1.
2. **Shader-compilation time budget.** The utility library adds ~7000 lines of preamble. Runtime `device.makeLibrary(source:)` compilation may become noticeable at launch. Measure and consider precompiled Metal archives (AIR) if it exceeds 500 ms.
3. **Texture memory for baked normal / height maps.** POM requires heightmaps. Ceramic / concrete / bark presets want real textures, not just procedural. Where do these ship? Git LFS alongside ML weights? Size ceiling?
4. **Reference image authorship.** Matt curates, but for 20+ presets that's significant curation work. Can Phase V.5 be incremental — each preset-uplift session ships both the shader and the reference images?
5. **Matt-review cadence.** The rubric says "Matt signs off on reference frame match." For 7 uplift increments (V.7–V.13) that's 7+ review gates. Compress via batched review sessions, or distributed throughout?

These do not block Phase V from starting. V.1 (noise + PBR utility library expansion) can begin today.
