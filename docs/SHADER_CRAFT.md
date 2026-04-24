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
2. Study the 3–5 reference images curated there. Each reference has annotations specifying which visual traits are mandatory and which are decorative.
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

Every new preset requires a VISUAL_REFERENCES folder before its first session prompt can be written. Matt owns the references (they're curated, not AI-generated). Claude Code sessions reference them by filename:

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
float3 curl_noise(float3 p, float e = 0.01) {
    float n1 = fbm8(p + float3(e, 0, 0)).x - fbm8(p - float3(e, 0, 0)).x;
    float n2 = fbm8(p + float3(0, e, 0)).x - fbm8(p - float3(0, e, 0)).x;
    float n3 = fbm8(p + float3(0, 0, e)).x - fbm8(p - float3(0, 0, e)).x;
    return float3(n2 - n3, n3 - n1, n1 - n2) / (2.0 * e);
}
```

Use for: particle flow in Murmuration successors, water advection in Ferrofluid Ocean, smoke/mist advection, Arachne dust-mote drift.

### 3.6 Worley-Perlin blend

Worley (cellular) noise produces distinct features — cells, cracks, spots. Blending Worley into fBM gives "fBM with character" — streaked, veined, marbled.

```metal
// Shaders/Utilities/Noise/WorleyFBM.metal (Increment V.1)
float worley_fbm(float3 p) {
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

### 4.6 Ferrofluid (Rosensweig spikes)

**Use for:** Ferrofluid Ocean. This preset's fidelity hinges on this recipe.

Ferrofluid surfaces under magnetic field form a lattice of conical spikes (Rosensweig instability). The spike array is not perfectly regular — it has hexagonal tendencies with domain defects. Between the spikes the surface is nearly mirror-metal.

**Recipe for the SDF:**

```metal
// Field at position p: returns height displacement
float ferrofluid_field(float3 p, float field_strength, float t) {
    // Hexagonal close-pack of spike centers with noise-driven defects
    float2 xz = p.xz;
    float2 hex = hex_tile(xz * 0.8);   // from Utilities/Geometry
    float jitter = fbm8(float3(hex, 0) * 2.0) * 0.3;
    float2 center = hex + jitter;

    float d = length(xz - center);
    // Conical spike profile with bell-curve falloff
    float spike = exp(-d * d * 40.0);
    // Time-animated with slow rotational flow
    spike *= 0.5 + 0.5 * sin(t * 0.8 + hex.x * 2.0 + hex.y * 1.3);
    return spike * field_strength * 0.15;
}

float sdf_ferrofluid(float3 p, float field_strength, float t) {
    float base_y = 0.0;
    float spikes = ferrofluid_field(p, field_strength, t);
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

### 4.10–4.20 Summary recipes

The following are single-paragraph recipes; expand to full Metal during Increment V.4 when the cookbook is formalized.

**4.10 Gold.** `albedo = float3(1.0, 0.78, 0.34); roughness = 0.15; metallic = 1.0;` with fine scratch fBM on normal at 50× scale, amplitude 0.03.

**4.11 Copper with patina.** Base copper `albedo = float3(0.95, 0.60, 0.36); metallic = 1.0`, patina layer `albedo = float3(0.15, 0.55, 0.45); metallic = 0.0`, mix mask from `worley_fbm(wp * 2.0) > 0.6` — patina in crevices, clean copper on peaks. Use AO as mask modifier.

**4.12 Velvet (retro-reflective fuzz).** Oren-Nayar diffuse with `sigma = 0.35`, plus a Fresnel-driven fuzz term that brightens at grazing angles (opposite of normal Fresnel): `fuzz = pow(1.0 - NdotV, 2.0) * fuzz_color * 0.5`. Add to emission for performance.

**4.13 Ceramic (clear-coat).** Saturated diffuse base + dielectric clear coat. `albedo = strong_color; roughness = 0.6; metallic = 0.0;` with composite stage adding a second specular lobe at `roughness_coat = 0.05, F0_coat = 0.04`.

**4.14 Ocean water.** Gerstner-wave displacement for macro swells, fbm8 for capillary ripples, Fresnel-weighted specular over deep-water absorption, foam mask on wave crests via displacement-derivative-magnitude threshold.

**4.15 Ink (2D stylized).** Flat emissive with flow-field UV distortion. `albedo = 0; metallic = 0; emission = ink_color * flow_sample(wp.xy, time, flow_texture)`.

**4.16 Granite.** `worley_fbm(wp * 2.0)` for speckle mask over three color stops (dark matrix, medium feldspar, bright mica highlights). Triplanar projection. Low roughness on mica inclusions (0.15), high elsewhere (0.85).

**4.17 Marble veining.** Curl-noise-warped Perlin for veins, sharp color transition via `smoothstep(0.48, 0.52, veins)`. Near-white base, deep-saturation vein color. Subtle SSS term for luminous translucency.

**4.18 Bioluminescent chitin.** Near-black base (`albedo = float3(0.02)`), iridescent thin-film specular (wavelength-dependent F0 from thickness-driven interference), rim emission scaled by `NdotV` inversion. Perfect for Arachne spider easter-egg carapace.

**4.19 Sand with glints.** Base `albedo = float3(0.85, 0.70, 0.50); roughness = 0.9; metallic = 0.0`. Glints: hash-lattice `grain_hash(wp * 500.0) > 0.992` returns isolated sparkle points with `roughness = 0.05, emission = white * 2.0`.

**4.20 Concrete (triplanar POM).** Gray base with variation via `worley_fbm`, POM depth map driven by `fbm8(wp * 5.0)`, triplanar-blended to avoid stretching on vertical faces. Grunge overlay via second fBM pass multiplied in at 0.25 strength.

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
float3 apply_fog(float3 color, float depth, float3 fog_color, float fog_density) {
    float fog_factor = 1.0 - exp(-depth * fog_density);
    return mix(color, fog_color, fog_factor);
}
```

Set `fog_color` to match the scene's sky or horizon color, not gray. Grey fog looks like a printing defect.

### 6.2 Volumetric light shafts (god rays)

**Use for:** Glass Brutalist through-window lighting, any preset with dramatic directional light through a structured environment.

Ray-march through the scene sampling the shadow map along each primary-visible ray, accumulating scattered light per step proportional to local fog density and phase function.

```metal
float3 volumetric_light_shafts(float3 ro, float3 rd, float3 L, depthTexture2d shadow_map) {
    float3 col = float3(0.0);
    float t = 0.0;
    float step = 0.15;
    for (int i = 0; i < 48; ++i) {
        float3 p = ro + rd * t;
        // Sample shadow map: is p in light?
        float shadow = sample_shadow(shadow_map, p);
        float density = 0.05 + 0.1 * fbm8(p * 0.5);
        // Henyey-Greenstein phase in ray direction
        float cos_theta = dot(rd, L);
        float phase = (1.0 - 0.3 * 0.3) / pow(1.0 + 0.3*0.3 - 0.6 * cos_theta, 1.5);
        col += shadow * density * phase * step;
        t += step;
    }
    return col * 0.3;   // intensity scale
}
```

Cost: ~1.5 ms at 1080p on Tier 2 with 48 steps. Sample at half-res + upscale if budget tight.

### 6.3 Dust motes

**Use for:** Arachne spider easter-egg reveal, Gossamer bioluminescent ambient, any scene that wants air-as-material.

Approach A: compute-particle system, 5000–20000 dust motes advected by curl noise, rendered as sprite quads. Lit by scene lights via simple Lambert.

Approach B (cheaper): screen-space particle overlay in post-process pass. Sample a 2D noise texture offset by `time * drift_velocity`, threshold for sparkle locations, add to bloom.

Approach B costs <0.5 ms; Approach A 2–3 ms. Both visibly upgrade "empty air" to "inhabited space."

### 6.4 Volumetric bloom (shaped)

The default `PostProcessChain` bloom (ACES composite + Gaussian pyramid) is adequate but uniform. Shaped bloom — where high-intensity pixels bloom more aggressively along specific directions — is what makes "bright emissive" look like "actual light source."

Two shaping approaches:

- **Anamorphic streaks**: horizontal stretch of bloom, 3× wider than vertical. Instant sci-fi look.
- **Star-point spikes**: 4-point or 6-point spikes extending from brightest pixels. Photographic lens flare aesthetic.

Both are ~0.3 ms additions to the existing bloom chain. Implement as optional flags per-preset in `PresetDescriptor`.

---

## 7. SDF Craft

### 7.1 Smooth union with multi-node blending

`opSmoothUnion` as commonly written blends two SDFs. Most ray-march scenes need to blend N SDFs (N > 2) without nesting binary unions (which causes visible triple-points).

```metal
float sd_smooth_union_multi(thread float distances[], int count, float k) {
    float result = 1e10;
    float weight_sum = 0.0;
    for (int i = 0; i < count; ++i) {
        float h = exp(-distances[i] / k);
        result += distances[i] * h;
        weight_sum += h;
    }
    return log(weight_sum) * -k + result / weight_sum;   // exponential-smooth-min form
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
float3 sdf_normal(float3 p, float epsilon = 0.001) {
    const float2 k = float2(1.0, -1.0);
    return normalize(
        k.xyy * scene_sdf(p + k.xyy * epsilon) +
        k.yyx * scene_sdf(p + k.yyx * epsilon) +
        k.yxy * scene_sdf(p + k.yxy * epsilon) +
        k.xxx * scene_sdf(p + k.xxx * epsilon)
    );
}
```

Four scene evaluations. Use this, not the six-tap central difference.

### 7.4 Adaptive sphere tracing

Fixed-step ray march burns cycles. Sphere tracing is the standard SDF march. Adaptive sphere tracing further accelerates by over-stepping when SDF is positive and retreating if surface missed.

```metal
struct RayHit {
    bool hit;
    float3 position;
    int steps;
};

RayHit march_adaptive(float3 ro, float3 rd, int max_steps, float max_dist) {
    RayHit h;
    h.hit = false;
    float t = 0.0;
    float prev_d = 1e10;
    for (int i = 0; i < max_steps; ++i) {
        float3 p = ro + rd * t;
        float d = scene_sdf(p);
        if (d < 0.001 * t) {
            h.hit = true;
            h.position = p;
            h.steps = i;
            return h;
        }
        if (t > max_dist) break;
        // Adaptive step: over-step slightly when SDF gradient is shallow
        float over_relax = 1.2;
        t += d * (d < prev_d ? over_relax : 1.0);
        prev_d = d;
    }
    h.steps = max_steps;
    return h;
}
```

Cost: ~20% fewer steps on average than basic sphere tracing. Worth it at max_steps = 64+.

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

Naive triplanar of normal maps produces incorrect results — the tangent frame differs per axis plane. The fix re-orients the tangent-space normals into world space per axis:

```metal
float3 triplanar_normal(float3 wp, float3 n, float tiling) {
    float3 blend = pow(abs(n), float3(4.0));
    blend /= dot(blend, float3(1.0));

    float3 nx = sample_normal_map(wp.yz * tiling);
    float3 ny = sample_normal_map(wp.xz * tiling);
    float3 nz = sample_normal_map(wp.xy * tiling);

    // Reorient each axis projection
    nx = float3(0.0, nx.y, nx.x) * sign(n.x);
    ny = float3(ny.x, 0.0, ny.y) * sign(n.y);
    nz = float3(nz.x, nz.y, 0.0) * sign(n.z);

    return normalize(n + nx * blend.x + ny * blend.y + nz * blend.z);
}
```

### 8.3 Parallax occlusion mapping (POM)

**Use for:** making concrete, bark, stone walls look like they have real depth rather than a normal map lie.

POM samples a heightmap along the view ray to find the correct surface displacement point. Expensive but the visual difference is dramatic.

```metal
float2 parallax_occlusion(texture2d<float> height_tex, sampler s, float2 uv, float3 view_ts, float depth_scale) {
    const int max_steps = 32;
    float layer_depth = 1.0 / float(max_steps);
    float current_depth = 0.0;

    float2 uv_step = view_ts.xy / view_ts.z * depth_scale / float(max_steps);
    float2 current_uv = uv;
    float current_height = 1.0 - height_tex.sample(s, current_uv).r;

    for (int i = 0; i < max_steps; ++i) {
        if (current_depth >= current_height) break;
        current_uv -= uv_step;
        current_depth += layer_depth;
        current_height = 1.0 - height_tex.sample(s, current_uv).r;
    }

    // Linear interpolation between last two steps
    float2 prev_uv = current_uv + uv_step;
    float prev_height = 1.0 - height_tex.sample(s, prev_uv).r - (current_depth - layer_depth);
    float current_delta = current_height - current_depth;
    float t = current_delta / (current_delta - prev_height);
    return mix(current_uv, prev_uv, t);
}
```

Cost: heavy — 32 texture samples worst case. ~1.0 ms per full-screen POM pass at 1080p on Tier 2. Use sparingly on hero surfaces only.

### 8.4 Detail normals

Layer multiple normal-map scales: a macro normal map at base UV frequency, plus a detail normal at 20× UV frequency. Combine properly:

```metal
float3 combine_normals(float3 base, float3 detail) {
    // UDN blend: adds detail without flattening
    return normalize(float3(base.xy + detail.xy, base.z * detail.z));
}
```

Use for: bark (bark grooves + fine texture), sand (dunes + grain), any weathered surface.

### 8.5 Flow maps

For liquid surfaces: sample a 2D texture encoding 2D flow-velocity vectors in RG channels. Offset UVs per frame by that flow vector. Two-phase mixing prevents stretching:

```metal
float3 flow_sample(texture2d<float> base, texture2d<float> flow, sampler s, float2 uv, float time) {
    float2 flow_vec = flow.sample(s, uv).rg * 2.0 - 1.0;
    float phase1 = fract(time * 0.5);
    float phase2 = fract(time * 0.5 + 0.5);
    float2 uv1 = uv - flow_vec * phase1 * 0.1;
    float2 uv2 = uv - flow_vec * phase2 * 0.1;
    float3 sample1 = base.sample(s, uv1).rgb;
    float3 sample2 = base.sample(s, uv2).rgb;
    float blend = abs(phase1 - 0.5) * 2.0;
    return mix(sample1, sample2, blend);
}
```

Use for: Ferrofluid Ocean surface flow, ink-style presets, river-like preset concepts.

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

V.1 primitive costs (single full-screen pass, Tier 2 / M3, 1080p):

| Recipe | Cost on Tier 2 | Notes |
|---|---|---|
| `perlin3d` single call | ~0.04 ms | Baseline noise primitive |
| `simplex3d` single call | ~0.05 ms | Slightly faster gradient computation |
| `worley3d` single call | ~0.08 ms | 27-cell neighbourhood |
| `fbm4` screen-space | ~0.18 ms | 4 × perlin3d |
| `fbm8` screen-space | 0.8 ms | Heavy; compute per-hit, not per-pixel |
| `fbm12` screen-space | ~1.1 ms | High detail; per-hit only |
| `warped_fbm` screen-space | 5.5 ms | 7 × fbm8; use only where essential |
| `ridged_mf` | ~0.6 ms | 6 octaves; output [0, 1] |
| `curl_noise` single sample | ~0.05 ms | 6 × fbm8 FD; cheap per-call, avoid per-pixel |
| `fresnel_schlick` | <0.01 ms | Single pow(); near free |
| `ggx_d + ggx_g_smith` | ~0.01 ms | Two sqrt + few muls; use freely |
| `brdf_cook_torrance` | ~0.02 ms | Full PBR: D + G + F + diffuse |
| `brdf_oren_nayar` | ~0.02 ms | Two acos + trig; avoid in tight loops |
| `brdf_ashikhmin_shirley` | ~0.03 ms | Anisotropic Phong; two pow() |
| `fiber_marschner_lite` | ~0.02 ms | Two acos + exp; per-hit only |
| `thinfilm_rgb` | ~0.03 ms | cos(phase) × 3 wavelengths |
| `sss_backlit` | ~0.01 ms | Single pow() + dot |
| `triplanar_sample` (RGB) | 0.3 ms per material | 3 samples + blend |
| `triplanar_normal` | 0.4 ms per material | 3 normal samples + reorient |
| `parallax_occlusion` full-screen | 1.0 ms | 32 steps worst case |
| `mat_silk_thread` | 0.8 ms per hit | Marschner lobes |
| `mat_ferrofluid` spike field | 1.5 ms | Hex-tile + fbm |
| `volumetric_light_shafts` | 1.5 ms | 48 steps half-res |
| `sample_cloud` full pass | 3.0 ms | 64 steps × 6 shadow samples |

Note: V.1 primitive costs are estimates based on operation-count analysis relative to benchmarked fbm8. Formal profiling via `PresetPerformanceTests` should validate per-preset numbers.

### 9.5 Profiling every new preset

Before a new preset is certified: run `swift test --filter PresetPerformanceTests` with synthetic 60-second captures on silence, steady mid-energy, and beat-heavy fixtures from `Increment 5.2`. Record p50 / p95 / p99 / max frame time. Any p95 > tier budget is a fail.

---

## 10. Per-Preset Fidelity Playbook

Concrete uplift recipes for the five presets Matt called out. Each references sections above.

### 10.1 Arachne (V.7)

**Current state:** 3D SDF ray march of spider webs. Cylindrical silk tubes, uniform glow. Reads as clipart.

**Target:** nature-documentary close-up of a dew-covered orb-weaver web at dawn, bioluminescent instead of dew-lit.

**Uplift plan:**

1. **Macro:** keep current web-pool structure (D-041). Add per-web organic variation — tilt jitter, hub-offset jitter, strand-count jitter (11–17 radial per web). §7.1 smooth-union for the web-on-web intersections.
2. **Meso:** per-strand sag/tension variation. Each radial thread subtly droops based on its length (longer = saggier). Spiral threads have micro-wobble from wind. Implement as per-vertex displacement in mesh shader, or per-segment in SDF.
3. **Micro:** adhesive droplets on spiral threads (the sticky capture threads have beaded glue; the radial spokes do not — silk biology). Procedurally place droplets at 8–12 px spacing along spiral threads via hash-lattice. Render as small spheres with dielectric material.
4. **Specular:** silk thread material from §4.3 (Marschner-lite). Narrow axial highlight on every thread. Adhesive droplets get mirror specular.
5. **Atmosphere:** dust-mote field (§6.3) at low density behind web. Volumetric hint of mist (0.02 fog) so web reads against spatial air, not void.
6. **Lighting:** bioluminescent (§5.3) — silk emission scaled by `stems.drums_beat_rel`. Rim back-light (cool blue) to edge-light the silk from behind.
7. **Audio reactivity:** keep current stage lifecycle; modulate only emission intensity and dust-mote density with music. Web geometry stays mostly static (D-020 principle — structure stays solid).

**Budget:** ~5.5 ms on Tier 2 (silk material is the heaviest component).

**Sessions estimated:** 3 (geometry + variation / materials / polish + audio routing).

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
