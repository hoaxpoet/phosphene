// RidgedMultifractal.metal — Ridged multifractal noise for sharp-crest topology.
//
// Ridged noise inverts absolute Perlin values and squares them, producing
// sharp bright crests at zero-crossings and dark valleys elsewhere.
// Ideal for mountains, erosion features, bark ridges, rock strata.
//
// Reference: Musgrave 1994 "The Synthesis and Rendering of Eroded Fractal Terrains",
//            SHADER_CRAFT.md §3.3.
//
// Depends on: Perlin.metal (perlin3d)
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

/// Ridged multifractal noise, 6 octaves.
/// `H` = Hurst exponent (default 0.5; lower = sharper ridges).
/// Output: approximately [0, 1], with sharp bright crests near 1.
static inline float ridged_mf(float3 p, float H = 0.5) {
    float a = 1.0, f = 1.0, sum = 0.0, norm = 0.0;
    for (int i = 0; i < 6; ++i) {
        float n = perlin3d(p * f);
        n = 1.0 - abs(n);   // invert: zero-crossings become bright crests
        n *= n;              // sharpen crests
        sum  += a * n;
        norm += a;
        a    *= H;
        f    *= 2.0;
    }
    return sum / norm;
}
