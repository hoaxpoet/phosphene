// FerrofluidMesh.metal — Mesh + vertex-displacement G-buffer path for Ferrofluid Ocean.
//
// V.9 Session 4.5c Phase 1 round 12 (Step B): replaces the SDF ray-march
// path for Ferrofluid Ocean only. Tessellated quad mesh covers the world
// patch; the vertex stage samples the baked spike heightmap and displaces
// each vertex along +Y; the fragment stage outputs the G-buffer in the
// same format the existing `raymarch_lighting_fragment` reads — so the
// existing matID == 2 Leitl four-layer material path runs unchanged.
//
// Architectural parity with Leitl's `spikes.vert.glsl`:
//   - 256×256 tessellated plane covering the world patch
//   - Heightmap sample at vertex UV → vertex Y displacement
//   - Normal via cross product of finite-differenced neighbor positions
//     (matches Leitl's `cross(t-p, p-b)` recipe)
//
// Differences from SDF path:
//   - No ray march. Rasterization fills pixels from displaced triangles.
//   - No `sceneSDF`. Heightmap is the only geometry source.
//   - No central-differences normal in fragment. Normal comes from vertex
//     stage cross product, interpolated by rasterizer.
//   - No AO (set to 1.0). Could add later if visible occlusion needed.

#include <metal_stdlib>
using namespace metal;

// Common.metal is concatenated before this file by ShaderLibrary's
// alphabetical sort — FeatureVector / StemFeatures / SceneUniforms are
// in scope without an explicit `#include`.

// MARK: - Vertex IO

/// Mesh vertex input. Each vertex carries its local-XZ position (Y=0 before
/// displacement) and a UV that addresses the heightmap. `FerrofluidMesh.swift`
/// generates these in a regular grid covering the world patch.
struct FerrofluidMeshVertex {
    float3 position [[attribute(0)]];   // (x, 0, z) in world space pre-displacement
    float2 uv       [[attribute(1)]];   // [0, 1] addressing the heightmap
};

/// Interpolated outputs from vertex → fragment. Worldpos + normal are
/// needed by the fragment for G-buffer output; depth is computed from
/// the rasterizer's clip-space position.
struct FerrofluidMeshVaryings {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
};

// MARK: - Audio routing helpers (mirror FerrofluidOcean.metal but inline)

/// D-019 stem warmup blend — `liveGate ≈ 0` at silence, `≈ 1` once stems
/// produce confident output. Same formula as `fo_stem_warmup_blend` in
/// FerrofluidOcean.metal.
static inline float fmesh_stem_warmup_blend(constant StemFeatures& stems) {
    float total = stems.vocals_energy + stems.drums_energy
                + stems.bass_energy   + stems.other_energy;
    return smoothstep(0.02, 0.06, total);
}

/// Spike strength routed identically to `fo_spike_strength` in
/// FerrofluidOcean.metal. Kept inline here so the mesh path doesn't
/// depend on the SDF preset's MSL — the two paths are independent.
static inline float fmesh_spike_strength(constant FeatureVector& f,
                                          constant StemFeatures& stems) {
    float liveGate = fmesh_stem_warmup_blend(stems);
    constexpr float kSpikeStemBaseline   = 2.0;
    constexpr float kSpikeStemModulation = 0.7;
    constexpr float kSpikeProxyGain      = 1.5;
    float proxyDev  = max(0.0, f.bass_dev);
    float stemDev   = max(0.0, stems.bass_energy_dev);
    float warmupStr = proxyDev * kSpikeProxyGain;
    float steadyStr = kSpikeStemBaseline + stemDev * kSpikeStemModulation;
    return mix(warmupStr, steadyStr, liveGate);
}

// MARK: - Constants

/// World-space height factor — multiplies the [0, 1] heightmap sample
/// times spike_strength. Mirrors `fo_ferrofluid_field_sampled`'s
/// `* 0.15` constant so the mesh path produces the same spike heights
/// the prior SDF path produced at the same spike_strength.
constant float kFerrofluidMeshHeightFactor = 0.15;

/// Heightmap UV epsilon for neighbor sampling in the normal computation.
/// 1.0 / mesh-segments-per-side. Matches one mesh-segment world distance,
/// so the computed normal is consistent with the rasterized triangle's
/// orientation. (256 segments → 1/256 ≈ 0.0039)
constant float kFerrofluidMeshNormalEps = 0.00390625;

/// World span the heightmap covers, in X and Z. Must match
/// `FerrofluidParticles.worldSpan` (20.0) — used to convert UV-space
/// derivatives to world-space tangent lengths.
constant float kFerrofluidMeshWorldSpan = 20.0;

// MARK: - Vertex shader

/// Sample the heightmap at `uv`, return world-space Y displacement
/// scaled by `spike_strength`. Clamp-to-zero address mode (set on the
/// sampler in Swift) → vertices outside the heightmap patch get zero
/// displacement (flat substrate at the edges).
static inline float fmesh_sample_height(texture2d<float> heightTex,
                                         sampler heightSamp,
                                         float2 uv,
                                         float spikeStrength) {
    float h = heightTex.sample(heightSamp, uv).r;
    return h * spikeStrength * kFerrofluidMeshHeightFactor;
}

vertex FerrofluidMeshVaryings ferrofluid_mesh_vertex(
    FerrofluidMeshVertex in        [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant StemFeatures&  stems    [[buffer(3)]],
    constant SceneUniforms& scene    [[buffer(4)]],
    texture2d<float>        heightTex [[texture(10)]]
) {
    constexpr sampler heightSamp(coord::normalized,
                                  filter::linear,
                                  address::clamp_to_zero);

    float spikeStr = fmesh_spike_strength(features, stems);

    // Centre sample — drives this vertex's own Y displacement.
    float yCenter = fmesh_sample_height(heightTex, heightSamp,
                                         in.uv, spikeStr);

    // Neighbour samples — drive the normal via cross product. Sample at
    // ±eps in U and V so the derivative is symmetric (matches the
    // central-differences pattern in the SDF path's normal estimation).
    float yRight = fmesh_sample_height(heightTex, heightSamp,
                                        in.uv + float2(kFerrofluidMeshNormalEps, 0.0),
                                        spikeStr);
    float yLeft  = fmesh_sample_height(heightTex, heightSamp,
                                        in.uv - float2(kFerrofluidMeshNormalEps, 0.0),
                                        spikeStr);
    float yFwd   = fmesh_sample_height(heightTex, heightSamp,
                                        in.uv + float2(0.0, kFerrofluidMeshNormalEps),
                                        spikeStr);
    float yBack  = fmesh_sample_height(heightTex, heightSamp,
                                        in.uv - float2(0.0, kFerrofluidMeshNormalEps),
                                        spikeStr);

    // World displacement vector.
    float3 displaced = float3(in.position.x, in.position.y + yCenter, in.position.z);

    // Tangent vectors in world space. UV-space epsilon maps to world-space
    // distance via worldSpan: dWorld = (eps × 2) × worldSpan in the X / Z
    // directions. Heights at ±eps neighbours yield the Y component.
    float worldEps = kFerrofluidMeshNormalEps * kFerrofluidMeshWorldSpan;
    float3 tangentX = float3(2.0 * worldEps, yRight - yLeft, 0.0);
    float3 tangentZ = float3(0.0, yFwd - yBack, 2.0 * worldEps);

    // Surface normal — cross product, oriented so +Y is "up" for a flat
    // surface. tangentX × tangentZ gives a vector pointing in +Y for the
    // expected winding (right-hand rule with X to the right, Z forward).
    float3 normalWS = normalize(cross(tangentZ, tangentX));

    // Build view-projection from scene uniforms. Phosphene doesn't ship a
    // pre-multiplied view-projection matrix in SceneUniforms; reconstruct
    // from camera basis vectors + FOV. Same math the SDF G-buffer fragment
    // uses to build ray directions, run in reverse to project a world
    // point to clip space.
    float3 camPos = scene.cameraOriginAndFov.xyz;
    float3 camFwd = scene.cameraForward.xyz;
    float3 camRt  = scene.cameraRight.xyz;
    float3 camUp  = scene.cameraUp.xyz;
    float  yFov   = scene.cameraOriginAndFov.w;
    float  nearP  = scene.sceneParamsA.z;
    float  farP   = scene.sceneParamsA.w;
    float  aspect = scene.sceneParamsA.y;

    // Camera-relative vector.
    float3 toPoint = displaced - camPos;

    // Project onto camera basis to get view-space coordinates.
    float viewX = dot(toPoint, camRt);
    float viewY = dot(toPoint, camUp);
    float viewZ = dot(toPoint, camFwd);

    // Standard Metal/D3D perspective projection. Clip-space depth in
    // [0, far] (post-divide [0, 1]). clip.w = viewZ so rasterizer's
    // perspective divide produces correct NDC.
    float tanHalfFov = tan(yFov * 0.5);
    float clipX = viewX / (tanHalfFov * aspect);
    float clipY = viewY / tanHalfFov;
    float clipZ = viewZ * farP / (farP - nearP)
                - farP * nearP / (farP - nearP);
    float clipW = viewZ;

    FerrofluidMeshVaryings out;
    out.clipPosition  = float4(clipX, clipY, clipZ, clipW);
    out.worldPosition = displaced;
    out.worldNormal   = normalWS;
    return out;
}

// MARK: - Fragment shader

/// G-buffer output (same layout as `GBufferOutput` in
/// PresetLoader+Preamble.swift — must stay byte-identical so the
/// existing `raymarch_lighting_fragment` reads correctly).
struct FerrofluidMeshGBufferOutput {
    float4 gbuf0 [[color(0)]];   // (depth, matID, 0, 0) — rg16Float
    float4 gbuf1 [[color(1)]];   // (normal.xyz, AO)     — rgba8Snorm
    float4 gbuf2 [[color(2)]];   // (albedo, packedRM)   — rgba8Unorm
};

fragment FerrofluidMeshGBufferOutput ferrofluid_mesh_gbuffer_fragment(
    FerrofluidMeshVaryings  in    [[stage_in]],
    constant SceneUniforms& scene [[buffer(4)]]
) {
    FerrofluidMeshGBufferOutput out;

    // Depth: normalize view-space Z by far plane to match SDF path's
    // `depthNorm = t / farPlane`. View-Z for this point:
    float3 camPos = scene.cameraOriginAndFov.xyz;
    float3 camFwd = scene.cameraForward.xyz;
    float  farP   = scene.sceneParamsA.w;
    float  viewZ  = dot(in.worldPosition - camPos, camFwd);
    float  depthNorm = clamp(viewZ / farP, 0.0, 0.9999);

    // matID == 2 → routes to Leitl four-layer material in lighting pass.
    out.gbuf0 = float4(depthNorm, 2.0, 0.0, 0.0);

    // Normal (already normalized in vertex stage; rasterizer interpolation
    // can denormalize so renormalize). AO = 1.0 (no occlusion data).
    float3 normal = normalize(in.worldNormal);
    out.gbuf1 = float4(normal, 1.0);

    // Albedo: pitch-black per §4.6 `mat_ferrofluid` recipe — substrate is
    // pure metal, all visible color comes from the env reflection in the
    // matID == 2 lighting branch. Roughness 0.08 + metallic 1.0 packed
    // into the alpha byte per the SDF path's convention.
    constexpr float kFerrofluidAlbedoR = 0.02;
    constexpr float kFerrofluidAlbedoG = 0.03;
    constexpr float kFerrofluidAlbedoB = 0.05;
    constexpr float kFerrofluidRoughness = 0.08;
    constexpr float kFerrofluidMetallic  = 1.0;
    int rByte = int(clamp(kFerrofluidRoughness, 0.0, 1.0) * 15.0 + 0.5);
    int mByte = int(clamp(kFerrofluidMetallic,  0.0, 1.0) * 15.0 + 0.5);
    float packed = float((rByte << 4) | mByte) / 255.0;

    out.gbuf2 = float4(kFerrofluidAlbedoR,
                       kFerrofluidAlbedoG,
                       kFerrofluidAlbedoB,
                       packed);
    return out;
}
