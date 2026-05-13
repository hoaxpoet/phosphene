// RayMarch.metal — Lighting and composite passes for the deferred ray march pipeline.
//
// Increment 3.14: Multi-Pass Ray March Pipeline.
//
// This file contains the FIXED render passes that do NOT require the preset's
// scene SDF function:
//
//   raymarch_lighting_fragment   — reads G-buffer, evaluates Cook-Torrance PBR,
//                                  screen-space soft shadows, ambient occlusion.
//                                  Renders into a .rgba16Float lit scene texture.
//
//   raymarch_composite_fragment  — reads the lit .rgba16Float texture, applies ACES
//                                  filmic tone mapping, outputs to drawable format.
//
// The G-buffer pass (raymarch_gbuffer_fragment) is compiled per-preset in the
// preamble (PresetLoader+Preamble.swift) because it calls preset-defined sceneSDF()
// and sceneMaterial() functions.
//
// G-buffer layout (set by the G-buffer pass, read by the lighting pass):
//   texture(0)  .rg16Float      R = depth_normalized [0..1), 1.0 = sky/miss;
//                               G = preset matID (LM.1 / D-LM-matid):
//                                     0 = standard dielectric (default; full
//                                         Cook-Torrance + IBL + screen-space
//                                         soft shadows);
//                                     1 = emission-dominated dielectric — the
//                                         G-buffer's `albedo` channel carries
//                                         backlight intensity instead of
//                                         surface diffuse colour. The lighting
//                                         path skips Cook-Torrance + shadow
//                                         dispatch and instead returns
//                                         `albedo * kEmissionGain` plus a
//                                         small mood-tinted IBL ambient floor.
//                                         Used by Lumen Mosaic; reusable by
//                                         any future preset whose visible
//                                         colour is dominated by emission.
//   texture(1)  .rgba8Snorm     RGB = world-space normal [-1..1]; A = ambient occlusion [0..1]
//   texture(2)  .rgba8Unorm     RGB = albedo [0..1]; A = packed roughness (upper 4b) + metallic (lower 4b)
//
// SceneUniforms is defined in Common.metal (compiled in the same Renderer library).

#include <metal_stdlib>
using namespace metal;

// MARK: - matID emission-dominated tunables (LM.1 / D-LM-matid)

/// matID encoding range: gbuf0.g is `.rg16Float`. matID values must fit
/// within fp16's exact integer range [0, 2048]; values above 2048 silently
/// truncate on the half-float round-trip and `int(g0.g + 0.5)` would read
/// back the wrong matID. Phase LM ships matID 0 (standard dielectric) and
/// matID 1 (emission-dominated); future presets may extend up to 2048.

/// Emission gain for matID == 1 (emission-dominated dielectric).
/// The G-buffer's albedo channel carries backlight intensity scaled to [0, 1].
///
/// **LM.3.2 calibration round 4 (2026-05-10): 4.0 → 1.0.** The original 4×
/// gain was sized for the LM.1–LM.2 cream-baseline palette where cells
/// landed at low values (~0.4 max) and needed the boost to cross
/// PostProcessChain bloom's bright-pass threshold. LM.3.2 round 4 switched
/// `LumenMosaic.metal` to an HSV-driven palette where cells are saturated
/// jewel tones with channel max already near 0.9, and the 4× boost was
/// causing the harness's float→Unorm conversion to clip pure-channel cells
/// to muted pastels (e.g. (0.9, 0.13, 0.13) × 0.85 × 4 = (3.06, 0.46, 0.46)
/// → clips to (1.0, 0.46, 0.46) — pinkish-pastel instead of vivid red).
/// Production with PostProcessChain ACES tonemap would handle this, but
/// the M7-prep harness output (no tonemap) was misleading. Reducing to 1.0
/// keeps cell colours under 1.0 in linear space and the harness now
/// matches production. Bloom doesn't engage (cells stay below threshold)
/// LM.4.6 (2026-05-11): reset to 1.0. The 1.5 boost from LM.4.5.3 was
/// paired with a wide [0.30, 1.60] per-cell brightness range that
/// produced too many over-bright washed-out cells. LM.4.6 narrows the
/// brightness range to [0.85, 1.15] and lets the anchor-distribution
/// model carry visual identity through hue, not brightness — so the
/// emission gain returns to neutral.
constexpr constant float kLumenEmissionGain = 1.0;

/// Low IBL ambient floor for matID == 1.  Without it, an unlit cell (one with
/// no light agent contribution) would render as pure black, breaking D-019
/// silence fallback.  0.05 keeps the panel coloured at all times by adding
/// a small fraction of the IBL irradiance to the emission output.
constexpr constant float kLumenIBLFloor = 0.05;

// MARK: - Helpers

/// Reconstruct perspective ray direction for the given screen UV.
/// UV (0,0) = top-left; UV (1,1) = bottom-right.
/// Matches the fullscreen_vertex flip: uv.y = 1 - original_y, so uv.y increases downward.
static float3 rm_rayDir(float2 uv, constant SceneUniforms& s) {
    float2 ndc  = uv * 2.0 - 1.0;
    float  yFov = tan(s.cameraOriginAndFov.w * 0.5);
    float  xFov = yFov * s.sceneParamsA.y;  // * aspectRatio
    // Negate ndc.y: uv.y = 0 is top of screen; positive y_world = up.
    return normalize(s.cameraForward.xyz
                     + ndc.x * xFov * s.cameraRight.xyz
                     - ndc.y * yFov * s.cameraUp.xyz);
}

/// Unpack roughness and metallic from the single-byte G-buffer value.
/// Packing: byte = (int(roughness*15) << 4) | int(metallic*15), normalized to [0..1].
static void rm_unpackMaterial(float packed, thread float& roughness, thread float& metallic) {
    int byte   = int(packed * 255.0 + 0.5);
    roughness  = float(byte >> 4)       / 15.0;
    metallic   = float(byte  & 0xF)     / 15.0;
}

/// GGX normal distribution function.
static float rm_ggxD(float NdotH, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * d * d + 1e-6);
}

/// Smith geometry term (Schlick-GGX).
static float rm_smith(float NdotV, float NdotL, float roughness) {
    float r  = (roughness + 1.0);
    float k  = (r * r) / 8.0;
    float gv = NdotV / (NdotV * (1.0 - k) + k + 1e-6);
    float gl = NdotL / (NdotL * (1.0 - k) + k + 1e-6);
    return gv * gl;
}

/// Fresnel-Schlick approximation.
static float3 rm_fresnel(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

/// Exact Fresnel reflectance for a dielectric (non-conducting) interface.
/// Renderer-local port of `Utilities/PBR/Fresnel.metal :: fresnel_dielectric`
/// — the preset utility tree is only concatenated into the per-preset preamble
/// (PresetLoader+Utilities.swift), so RayMarch.metal (engine renderer library)
/// keeps its own copy. Keep in sync with the preset version if either changes.
static float rm_fresnel_dielectric(float cosI, float ior) {
    float cos_i = clamp(cosI, 0.0, 1.0);
    float sin2_t = (1.0 - cos_i * cos_i) / (ior * ior);
    if (sin2_t >= 1.0) return 1.0;  // total internal reflection
    float cos_t = sqrt(max(0.0, 1.0 - sin2_t));
    float rs = (cos_i - ior * cos_t) / (cos_i + ior * cos_t);
    float rp = (ior * cos_i - cos_t) / (ior * cos_i + cos_t);
    return (rs * rs + rp * rp) * 0.5;
}

/// Thin-film interference reflectance as wavelength-sampled RGB approximation.
/// Renderer-local port of `Utilities/PBR/Thin.metal :: thinfilm_rgb`. Used by
/// the matID == 3 branch (V.9 Session 2 / Ferrofluid Ocean) to compute the
/// view-dependent F0 of a thin oil-like film over a metallic substrate.
///
/// Keep in sync with the preset version if either changes.
static float3 rm_thinfilm_rgb(float VdotH, float thicknessNm,
                               float iorThin, float iorBase) {
    if (thicknessNm < 0.5) {
        float F0 = rm_fresnel_dielectric(1.0, iorBase);
        return float3(F0);
    }
    float cos_i  = clamp(VdotH, 0.0, 1.0);
    float sin2_t = (1.0 - cos_i * cos_i) / (iorThin * iorThin);
    float cos_t  = sqrt(max(0.0, 1.0 - sin2_t));

    const float3 lambda = float3(680.0, 550.0, 450.0);   // R G B peak wavelengths
    float  OPD    = 2.0 * iorThin * thicknessNm * cos_t;
    float3 phase  = (2.0 * M_PI_F * OPD) / lambda;

    float  F_in   = rm_fresnel_dielectric(cos_i, iorThin);
    float  F_out  = rm_fresnel_dielectric(cos_t, iorBase);
    float  F12    = F_out;
    float3 F01    = float3(F_in);
    float3 interference = F01 + F12 + 2.0 * sqrt(F_in * F12) * cos(phase);
    return clamp(interference * 0.5, 0.0, 1.0);
}

/// Cook-Torrance BRDF contribution for one light.
static float3 rm_brdf(float3 N, float3 V, float3 L,
                       float3 albedo, float roughness, float metallic) {
    float3 H      = normalize(V + L);
    float  NdotV  = max(dot(N, V), 0.0);
    float  NdotL  = max(dot(N, L), 0.0);
    float  NdotH  = max(dot(N, H), 0.0);
    float  VdotH  = max(dot(V, H), 0.0);

    float3 F0     = mix(float3(0.04), albedo, metallic);
    float3 F      = rm_fresnel(VdotH, F0);
    float  D      = rm_ggxD(NdotH, roughness);
    float  G      = rm_smith(NdotV, NdotL, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-6);
    float3 kd       = (1.0 - F) * (1.0 - metallic);
    float3 diffuse  = kd * albedo / M_PI_F;

    return (diffuse + specular) * NdotL;
}

/// Cook-Torrance with caller-supplied F0 (matID == 3 thin-film path).
/// Body mirrors `rm_brdf` with the F0-from-metallic line removed; callers
/// (e.g. the matID == 3 branch in raymarch_lighting_fragment) compute F0
/// via `rm_thinfilm_rgb(...)` at the view half-vector and pass it through.
/// `metallic` still parameterises the diffuse-vs-specular split via `kd`.
static float3 rm_brdf_with_F0(float3 N, float3 V, float3 L,
                               float3 albedo, float3 F0,
                               float roughness, float metallic) {
    float3 H      = normalize(V + L);
    float  NdotV  = max(dot(N, V), 0.0);
    float  NdotL  = max(dot(N, L), 0.0);
    float  NdotH  = max(dot(N, H), 0.0);
    float  VdotH  = max(dot(V, H), 0.0);

    float3 F      = rm_fresnel(VdotH, F0);
    float  D      = rm_ggxD(NdotH, roughness);
    float  G      = rm_smith(NdotV, NdotL, roughness);

    float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-6);
    float3 kd       = (1.0 - F) * (1.0 - metallic);
    float3 diffuse  = kd * albedo / M_PI_F;

    return (diffuse + specular) * NdotL;
}

/// Procedural sky gradient for miss pixels and environment reflections.
static float3 rm_skyColor(float3 rayDir) {
    float t       = 0.5 * (rayDir.y + 1.0);
    float3 horizon = float3(0.85, 0.90, 1.0);
    float3 zenith  = float3(0.10, 0.30, 0.8);
    return mix(horizon, zenith, t);
}

/// Shared "lighting tail" for matID == 0 (default Cook-Torrance) and matID == 3
/// (thin-film Cook-Torrance) — adds D-022 mood-tinted IBL ambient and applies
/// atmospheric fog to the caller's `directLit` contribution.
///
/// Extracting this tail eliminates the ~60-line copy-paste between the matID
/// branches and removes a class of Failed Approach #24 bug: the
/// `ambient *= scene.lightColor.rgb` line that propagates mood-valence
/// scene-wide is now in one place rather than one-per-matID. Future matID
/// branches (e.g. matID == 2 for the §5.8 stage-rig in V.9 Session 3) call
/// this helper after computing their own direct-light contribution.
///
/// Returns the final linear-HDR colour ready for ACES tone-mapping in the
/// composite pass. The caller wraps the result in `float4(..., 1.0)`.
static float3 rm_finishLightingPass(
    float3 directLit,
    float3 N, float3 V,
    float3 albedo, float roughness, float metallic, float ao,
    float depthNorm, float farPlane,
    float3 rayDir,
    constant SceneUniforms& scene,
    texturecube<float> iblIrradiance,
    texturecube<float> iblPrefiltered,
    texture2d<float>   iblBRDFLUT,
    sampler            iblSamp
) {
    // IBL ambient (diffuse + specular) — split-sum approximation.
    // Standard F0 path (not thin-film) so the iridescent shift stays
    // localised to direct specular highlights and doesn't saturate the
    // whole surface via the environment integral.
    float  NdotV       = max(dot(N, V), 0.0);
    float3 R           = reflect(-V, N);
    float3 F0          = mix(float3(0.04), albedo, metallic);
    float3 F_ibl       = rm_fresnel(NdotV, F0);
    float3 kd          = (1.0 - F_ibl) * (1.0 - metallic);

    float3 irradiance  = ibl_sample_irradiance(N, iblIrradiance, iblSamp);
    float3 prefColor   = ibl_sample_prefiltered(R, roughness, iblPrefiltered, iblSamp, 4);
    float2 brdfFactors = ibl_sample_brdf_lut(NdotV, roughness, iblBRDFLUT, iblSamp);
    float3 iblDiffuse  = kd * albedo * irradiance;
    float3 iblSpecular = prefColor * (F_ibl * brdfFactors.x + brdfFactors.y);
    float3 iblAmbient  = (iblDiffuse + iblSpecular) * ao;

    // Minimum ambient prevents fully black surfaces when IBL textures are
    // unbound (Apple Silicon Metal returns zero for unbound textures).
    float3 ambient = max(iblAmbient, albedo * 0.04 * ao);

    // D-022: tint the ambient by the scene light colour so valence shifts
    // propagate scene-wide. Indoor ray-march scenes are dominated by IBL
    // ambient and the direct light only catches surfaces facing it; without
    // this multiply, mood valence affects only the direct-lit pixels.
    ambient *= scene.lightColor.rgb;

    float3 litColor = directLit + ambient;

    // Atmospheric fog. fogColor takes the same lightColor tint so the
    // distance falloff stays palette-consistent.
    float  fogNear   = scene.sceneParamsB.x;
    float  fogFar    = scene.sceneParamsB.y;
    float  t         = depthNorm * farPlane;
    float  fogFactor = clamp((t - fogNear) / max(fogFar - fogNear, 0.001), 0.0, 1.0);
    float3 fogColor  = rm_skyColor(rayDir) * scene.lightColor.rgb;
    return mix(litColor, fogColor, fogFactor);
}

/// Screen-space soft shadow: march from surface toward the light along the G-buffer.
/// Returns a shadow factor in [0,1] where 0 = fully shadowed, 1 = fully lit.
static float rm_screenSpaceShadow(
    float2 fragUV,
    float3 worldPos,
    float3 lightDir,
    float  lightDist,
    texture2d<float> gbuf0,
    sampler samp,
    constant SceneUniforms& s
) {
    const int   kSteps    = 12;
    const float kBias     = 0.04;   // surface bias to avoid self-shadowing
    const float kPenumbra = 0.08;   // softness of shadow edge

    float farPlane    = s.sceneParamsA.w;
    float aspectRatio = s.sceneParamsA.y;
    float yFov        = tan(s.cameraOriginAndFov.w * 0.5);
    float xFov        = yFov * aspectRatio;

    float3 camPos    = s.cameraOriginAndFov.xyz;
    float3 camFwd    = s.cameraForward.xyz;
    float3 camRight  = s.cameraRight.xyz;
    float3 camUp     = s.cameraUp.xyz;

    float  stepSize  = lightDist / float(kSteps + 1);
    float  shadow    = 1.0;

    for (int i = 1; i <= kSteps; i++) {
        float3 samplePos = worldPos + lightDir * (float(i) * stepSize) + lightDir * kBias;

        // Project samplePos to screen UV.
        float3 toSample  = samplePos - camPos;
        float  sDepth    = dot(toSample, camFwd);
        if (sDepth <= 0.0) continue;

        float  sU = dot(toSample, camRight) / (sDepth * xFov);
        float  sV = dot(toSample, camUp)    / (sDepth * yFov);
        float2 sUV = float2(sU * 0.5 + 0.5, 0.5 - sV * 0.5);

        // Skip samples outside the screen.
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) continue;

        float sampledDepth = gbuf0.sample(samp, sUV).r;
        if (sampledDepth >= 0.999) continue;  // sky — no occlusion

        float sampledT   = sampledDepth * farPlane;
        float expectedT  = sDepth;

        // If G-buffer records a surface closer than our shadow ray sample,
        // something is blocking the path to the light → shadow.
        if (sampledT < expectedT - 0.1) {
            float penumbra = clamp((expectedT - sampledT) / kPenumbra, 0.0, 1.0);
            shadow = min(shadow, 1.0 - penumbra);
        }
    }
    return clamp(shadow, 0.0, 1.0);
}

// MARK: - Lighting Pass

/// Deferred PBR lighting pass for ray march presets.
///
/// Reads the three G-buffer textures written by `raymarch_gbuffer_fragment`,
/// evaluates Cook-Torrance BRDF with the scene's primary light, applies
/// screen-space soft shadows and ambient occlusion, samples IBL textures for
/// physically accurate environment ambient and specular reflections, and writes
/// a linear-HDR colour to the .rgba16Float lit scene texture.
///
/// IBL textures (Increment 3.16):
///   texture(9)  — irradiance cubemap       → diffuse ambient (ibl_sample_irradiance)
///   texture(10) — prefiltered env cubemap  → specular reflections (ibl_sample_prefiltered)
///   texture(11) — BRDF split-sum LUT       → Fresnel split factors (ibl_sample_brdf_lut)
/// When IBL textures are not yet bound, they return zero; the per-component max
/// against `albedo * 0.04 * ao` prevents fully black surfaces during warmup.
///
/// matID dispatch (LM.1 / D-LM-matid):
///   gbuf0.g carries a preset-supplied material flag.
///   matID == 0 (default) — full Cook-Torrance + screen-space soft shadows + IBL
///                          ambient and specular. Existing presets pre-LM.1.
///   matID == 1 (Lumen Mosaic) — emission-dominated dielectric. Albedo is
///                          treated as backlight intensity; the surface emits
///                          `albedo * kLumenEmissionGain` plus a small
///                          IBL-derived ambient floor. Cook-Torrance and the
///                          screen-space shadow march are skipped entirely so
///                          the path is cheap and deterministic regardless of
///                          scene-light placement. The 4× gain pulls bright
///                          cells over PostProcessChain's bloom threshold so
///                          backlight visibly bleeds across cell ridges; the
///                          0.05 IBL ambient floor keeps the panel coloured
///                          when the preset has no analytical lights yet.
///                          Tunable via the file-scope `kLumenEmissionGain`
///                          and `kLumenIBLFloor` constants below.
fragment float4 raymarch_lighting_fragment(
    VertexOut                   in        [[stage_in]],
    constant FeatureVector&     features  [[buffer(0)]],
    constant SceneUniforms&     scene     [[buffer(4)]],
    texture2d<float>            gbuf0     [[texture(0)]],   // rg16Float: depth, unused
    texture2d<float>            gbuf1     [[texture(1)]],   // rgba8Snorm: normal xyz, AO
    texture2d<float>            gbuf2     [[texture(2)]],   // rgba8Unorm: albedo, packed material
    texture2d<float>            noiseLQ        [[texture(4)]],
    texture2d<float>            noiseHQ        [[texture(5)]],
    texture3d<float>            noiseVol       [[texture(6)]],
    texture2d<float>            noiseFBM       [[texture(7)]],
    texture2d<float>            blueNoise      [[texture(8)]],
    texturecube<float>          iblIrradiance  [[texture(9)]],
    texturecube<float>          iblPrefiltered [[texture(10)]],
    texture2d<float>            iblBRDFLUT     [[texture(11)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    // IBL sampler: trilinear filtering for mip LOD-based roughness lookup.
    constexpr sampler iblSamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;

    // ── Sample G-buffer ────────────────────────────────────────────
    float4 g0 = gbuf0.sample(samp, uv);
    float4 g1 = gbuf1.sample(samp, uv);
    float4 g2 = gbuf2.sample(samp, uv);

    float depthNorm = g0.r;

    // Miss / sky pixel: depth == 1.0.
    //
    // Apply scene.lightColor.rgb tint only when fog is DISABLED.
    // Presets with fog (Glass Brutalist, Kinetic Sculpture) already
    // receive the same tint via the fog-colour path below
    // (fogColor = rm_skyColor(rayDir) * scene.lightColor.rgb), so
    // applying it here too collapses the cool-sky/warm-light contrast
    // that makes those scenes read as outdoor architecture.
    //
    // Presets with fog disabled (VL ships scene_fog: 0) need this path
    // to avoid the "neutral gray backdrop" failure — sky pixels that
    // ignore lightColor stay raw blue-gray even when valence warms
    // the direct light.
    //
    // Sentinel: the "no-fog" fallback in PresetDescriptor+SceneUniforms
    // returns fogFar = 1_000_000.  Any realistic fogFar is < 500.
    if (depthNorm >= 0.999) {
        float3 rd = rm_rayDir(uv, scene);
        bool fogDisabled = scene.sceneParamsB.y > 1.0e5;
        float3 sky = rm_skyColor(rd);
        return float4(fogDisabled ? sky * scene.lightColor.rgb : sky, 1.0);
    }

    // ── Reconstruct surface data ───────────────────────────────────
    float  farPlane = scene.sceneParamsA.w;
    float3 rayDir   = rm_rayDir(uv, scene);
    float3 worldPos = scene.cameraOriginAndFov.xyz + rayDir * (depthNorm * farPlane);

    // Normal is stored as-is in rgba8Snorm (values directly in [-1, 1]).
    float3 N  = normalize(g1.xyz);
    float  ao = g1.w;                       // ambient occlusion [0, 1]

    float3 albedo    = g2.rgb;
    float  roughness, metallic;
    rm_unpackMaterial(g2.a, roughness, metallic);

    // ── matID == 1 — frosted backlit glass (LM.1 / D-LM-matid) ─────
    // Lumen Mosaic and similar emission-dominated presets store their
    // backlight intensity in `albedo` rather than a surface diffuse colour.
    // Skip Cook-Torrance + screen-space shadow march for the dominant
    // emission term, but layer **photorealistic frosted-glass surface
    // character** on top of the backlight (LM.3.2 calibration round 5,
    // 2026-05-10): saturated cell colour softens toward white at cell
    // ridges (frost diffusion), specular sparkle catches the fbm8 frost
    // normal, and Fresnel edge sheen brightens cell-ridge silhouettes.
    // Without this, the panel renders as flat-painted Voronoi cells —
    // technically correct backlight but visually clipart-y. With it,
    // the panel reads as actual stained glass behind a frosted pane.
    //
    // Sky path (depth ≥ 0.999) returned at the gbuf-sample block above
    // before this dispatch is reached — sky pixels never observe matID
    // even when a preset writes matID = 1 to every hit (Lumen Mosaic).
    // matID values must fit fp16's exact integer range [0, 2048]; see
    // the kLumenEmissionGain block at the top of this file.
    int matID = int(g0.g + 0.5);
    if (matID == 1) {
        // **LM.3.2 round 7 (2026-05-10) — frost diffusion baked in
        // sceneMaterial, lighting path simplified.** Earlier rounds
        // tried to add frosted-glass surface character here (frost
        // scatter from normal deviation + procedural sparkle + Fresnel
        // edge sheen). Those approaches produced visible per-pixel
        // dot artifacts inside cells: the SDF relief geometry produced
        // sub-pixel normal noise that the normal-driven frost-scatter
        // term amplified into single-pixel white spots, and the
        // procedural sparkle hash period aliased with the cell scale
        // to produce a "dot in every cell" pattern artifact (Matt
        // 2026-05-10).
        //
        // Round 7 moves the frost diffusion to `LumenMosaic.metal`
        // sceneMaterial, where it's driven by the Voronoi `f2 - f1`
        // cell-edge distance directly — a large-scale, smooth signal
        // that produces clean cell-boundary white-mixing without
        // sub-pixel noise. The SDF relief amplitude is set to 0 (no
        // normal variation), so the panel's geometric normal stays a
        // clean flat (0, 0, -1) per pixel. Fresnel-driven edge sheen
        // and normal-driven frost scatter both collapse to zero with
        // a flat normal, so the lighting path returns to the round-4
        // baseline: pure emission + IBL ambient floor.
        float3 irradiance   = ibl_sample_irradiance(N, iblIrradiance, iblSamp);
        float3 ambientFloor = irradiance * kLumenIBLFloor * ao;
        return float4(albedo * kLumenEmissionGain + ambientFloor, 1.0);
    }

    // ── matID == 3 — metallic thin-film Cook-Torrance (V.9 Session 2) ──
    // Ferrofluid Ocean's spike material: pitch-black metallic substrate
    // with a thin-film interference layer producing a subtle blue-to-cyan
    // iridescent shift in highlights. F0 comes from rm_thinfilm_rgb at the
    // half-vector angle; everything else mirrors the default Cook-Torrance
    // path so D-022 mood-tinted IBL ambient and arousal-driven fog continue
    // to apply unchanged.
    //
    // Thickness 220 nm sits inside the "blue-to-cyan" interference band —
    // a subtle iridescent shift in spike highlights, not a rainbow oil-slick.
    // ior_thin 1.45 = silicone-oil-like (real ferrofluids are oil-based
    // suspensions). ior_base 1.0 = treat the metallic substrate as opaque;
    // the bottom-interface Fresnel is degenerate but rm_thinfilm_rgb's
    // approximation reads correctly at this setting.
    //
    // matID == 2 is reserved for Session 3 (D-125 stage-rig dispatch); the
    // thin-film F0 helper above is reusable inside that branch when it lands.
    if (matID == 3) {
        constexpr float kFerrofluidFilmThicknessNm = 220.0;
        constexpr float kFerrofluidFilmIORThin     = 1.45;
        constexpr float kFerrofluidFilmIORBase     = 1.0;

        // TODO(V.9 Session 4): modulate kFerrofluidFilmThicknessNm from audio
        // (deviation primitives per D-026) so the iridescent shift breathes
        // with the music. Hold at a fixed 220 nm in Session 2.

        float3 V         = normalize(scene.cameraOriginAndFov.xyz - worldPos);
        float3 lightPos  = scene.lightPositionAndIntensity.xyz;
        float  intensity = scene.lightPositionAndIntensity.w;
        float3 lColor    = scene.lightColor.xyz;

        float3 L         = lightPos - worldPos;
        float  lightDist = length(L);
        L                = normalize(L);
        float3 H         = normalize(L + V);
        float  VdotH     = max(dot(V, H), 0.0);
        float  attenuation = 1.0 / (1.0 + lightDist * lightDist);

        // Thin-film F0 replaces the standard mix(0.04, albedo, metallic).
        // Metallic = 1 → the diffuse term vanishes (kd = 0); we keep the
        // metallic parameter wired through for helper generality.
        float3 F0_thin = rm_thinfilm_rgb(VdotH,
                                         kFerrofluidFilmThicknessNm,
                                         kFerrofluidFilmIORThin,
                                         kFerrofluidFilmIORBase);

        float3 directLit = rm_brdf_with_F0(N, V, L, albedo, F0_thin, roughness, metallic)
                         * lColor * intensity * attenuation;

        float shadow = rm_screenSpaceShadow(uv, worldPos, L, lightDist, gbuf0, samp, scene);
        directLit *= shadow;

        return float4(rm_finishLightingPass(
            directLit, N, V, albedo, roughness, metallic, ao,
            depthNorm, farPlane, rayDir, scene,
            iblIrradiance, iblPrefiltered, iblBRDFLUT, iblSamp
        ), 1.0);
    }

    // ── Lighting ───────────────────────────────────────────────────
    float3 V         = normalize(scene.cameraOriginAndFov.xyz - worldPos);
    float3 lightPos  = scene.lightPositionAndIntensity.xyz;
    float  intensity = scene.lightPositionAndIntensity.w;
    float3 lColor    = scene.lightColor.xyz;

    float3 L         = lightPos - worldPos;
    float  lightDist = length(L);
    L                = normalize(L);

    // Inverse-square attenuation: prevents infinitely-repeating geometry (glass panels,
    // tiled corridors) from accumulating extreme HDR values. The `+ 1.0` prevents a
    // singularity when the surface is at the light position.
    float  attenuation = 1.0 / (1.0 + lightDist * lightDist);
    float3 directLit   = rm_brdf(N, V, L, albedo, roughness, metallic) * lColor * intensity * attenuation;

    // ── Screen-space soft shadow ───────────────────────────────────
    float shadow = rm_screenSpaceShadow(uv, worldPos, L, lightDist, gbuf0, samp, scene);
    directLit *= shadow;

    // ── IBL ambient (D-022 mood-tinted) + fog ──────────────────────
    // Shared with matID == 3 via rm_finishLightingPass. Future matID
    // branches (e.g. matID == 2 for the §5.8 stage-rig in V.9 Session 3)
    // compute their own direct-light contribution and call the same helper.
    return float4(rm_finishLightingPass(
        directLit, N, V, albedo, roughness, metallic, ao,
        depthNorm, farPlane, rayDir, scene,
        iblIrradiance, iblPrefiltered, iblBRDFLUT, iblSamp
    ), 1.0);
}

// MARK: - Depth Debug Pass

/// DEBUG: Visualize raw G-buffer, bypassing all lighting and bloom.
/// Left half:  depth map (white=near, dark=far, RED=sky/miss)
/// Right half: raw unlit albedo from G-buffer
fragment float4 raymarch_depth_debug_fragment(
    VertexOut        in    [[stage_in]],
    texture2d<float> gbuf0 [[texture(0)]],
    texture2d<float> gbuf2 [[texture(1)]],
    sampler          s     [[sampler(0)]]
) {
    float2 uv = in.uv;
    float depthNorm = gbuf0.sample(s, uv).r;

    if (uv.x < 0.5) {
        if (depthNorm >= 0.999) {
            return float4(1.0, 0.0, 0.0, 1.0);  // RED = miss/sky
        }
        float vis = 1.0 - depthNorm;
        return float4(vis, vis, vis, 1.0);
    } else {
        if (depthNorm >= 0.999) {
            return float4(0.2, 0.2, 0.3, 1.0);  // dark blue = sky
        }
        float3 albedo = gbuf2.sample(s, uv).rgb;
        return float4(albedo, 1.0);
    }
}

// MARK: - G-buffer Debug Pass

/// Diagnostic pass: copies gbuf2 (albedo/debug data) directly to the drawable.
///
/// Invoked when `RayMarchPipeline.debugGBufferMode == true`.
/// Bypasses the lighting pass, SSGI, and ACES tone-mapping so the raw colours
/// written by the G-buffer diagnostic quadrants reach the screen unmodified.
/// This makes the 4-quadrant GBUFFER_DEBUG visualization actually readable:
///   TL = green (hit) / red (miss)  [not muted grey after ACES]
///   TR = SDF sign at ray start
///   BL = step count greyscale
///   BR = hit depth greyscale / red on miss
fragment float4 raymarch_gbuffer_debug_fragment(
    VertexOut        in    [[stage_in]],
    texture2d<float> gbuf2 [[texture(0)]],
    sampler          samp  [[sampler(0)]]
) {
    // gbuf2 is .rgba8Unorm; sample values are already in [0,1] SDR — no tone-map needed.
    return gbuf2.sample(samp, in.uv);
}

// MARK: - Composite Pass

/// Composite the lit .rgba16Float scene texture to the SDR drawable.
///
/// Applies ACES filmic tone mapping. Invoked when the ray march pipeline is
/// used without a `PostProcessChain` for bloom. When bloom is desired, the
/// caller feeds `litTexture` directly into `PostProcessChain.runBloomAndComposite`.
fragment float4 raymarch_composite_fragment(
    VertexOut        in  [[stage_in]],
    texture2d<float> lit [[texture(0)]],
    sampler          s   [[sampler(0)]]
) {
    float3 hdr = lit.sample(s, in.uv).rgb;

    // ACES filmic tone mapping.
    float3 x = hdr;
    float3 mapped = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    mapped = clamp(mapped, 0.0, 1.0);

    return float4(mapped, 1.0);
}
