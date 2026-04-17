// PresetLoader+Preamble — Common Metal shader preamble prepended to all presets.

import Foundation
import os.log

private let preambleLogger = Logger(subsystem: "com.phosphene.presets", category: "Preamble")

// MARK: - Common Shader Preamble

extension PresetLoader {

    /// Shared Metal code prepended to every preset shader.
    /// Contains FeatureVector struct, VertexOut, fullscreen_vertex, color utilities,
    /// and the full ShaderUtilities function library loaded from the bundle resource.
    static let shaderPreamble: String = {
        let structPreamble = """
        #include <metal_stdlib>
        using namespace metal;

        #define FFT_BIN_COUNT 512
        #define WAVEFORM_CAPACITY 2048

        // Matches Swift FeedbackParams layout (8 floats = 32 bytes).
        struct FeedbackParams {
            float decay, base_zoom, base_rot;
            float beat_zoom, beat_rot, beat_sensitivity;
            float beat_value, _pad0;
        };

        // Matches Swift FeatureVector layout (48 floats = 192 bytes, MV-1).
        struct FeatureVector {
            float bass, mid, treble;
            float bass_att, mid_att, treb_att;
            float sub_bass, low_bass, low_mid, mid_high, high_mid, high_freq;
            float beat_bass, beat_mid, beat_treble, beat_composite;
            float spectral_centroid, spectral_flux;
            float valence, arousal;
            float time, delta_time;
            float _pad0, aspect_ratio;
            float accumulated_audio_time;
            // MV-1 deviation primitives (floats 26–34, D-026).
            // xRel = (x - 0.5) * 2.0 — centered at 0, ~±0.5 typical range.
            // xDev = max(0, xRel)     — positive deviation only (loud moments).
            // Use Rel for continuous drivers; Dev for accent/threshold drivers.
            float bass_rel, bass_dev;
            float mid_rel,  mid_dev;
            float treb_rel, treb_dev;
            float bass_att_rel, mid_att_rel, treb_att_rel;
            // Padding to 192 bytes (floats 35–48).
            float _pad1, _pad2, _pad3, _pad4, _pad5, _pad6, _pad7,
                  _pad8, _pad9, _pad10, _pad11, _pad12, _pad13, _pad14;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        // Full-screen triangle: 3 vertices, no vertex buffer needed.
        vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
            VertexOut out;
            out.uv = float2((vid << 1) & 2, vid & 2);
            out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
            out.uv.y = 1.0 - out.uv.y;
            return out;
        }

        // Per-stem audio features, bound at buffer(3). All zero during warmup.
        // Matches Swift StemFeatures layout (32 floats = 128 bytes, MV-1).
        struct StemFeatures {
            float vocals_energy;      float vocals_band0;
            float vocals_band1;       float vocals_beat;

            float drums_energy;       float drums_band0;
            float drums_band1;        float drums_beat;

            float bass_energy;        float bass_band0;
            float bass_band1;         float bass_beat;

            float other_energy;       float other_band0;
            float other_band1;        float other_beat;

            // MV-1 deviation primitives (floats 17–24, D-026).
            // xEnergyRel = (xEnergy - EMA) * 2.0 — centered at 0.
            // xEnergyDev = max(0, xEnergyRel)     — positive deviation only.
            float vocals_energy_rel;  float vocals_energy_dev;
            float drums_energy_rel;   float drums_energy_dev;
            float bass_energy_rel;    float bass_energy_dev;
            float other_energy_rel;   float other_energy_dev;

            // Padding to 128 bytes (floats 25–32).
            float _pad1, _pad2, _pad3, _pad4, _pad5, _pad6, _pad7, _pad8;
        };

        // ── Noise texture samplers (Increment 3.13) ───────────────────────────
        // TextureManager binds pre-computed noise textures at [[texture(4)]]–[[texture(8)]].
        // Declare the needed ones in your fragment function signature to sample them:
        //
        //   texture2d<float>  noiseLQ     [[texture(4)]]  — 256²  tileable Perlin FBM (.r8Unorm)
        //   texture2d<float>  noiseHQ     [[texture(5)]]  — 1024² tileable Perlin FBM (.r8Unorm)
        //   texture3d<float>  noiseVolume [[texture(6)]]  — 64³   tileable 3D FBM   (.r8Unorm)
        //   texture2d<float>  noiseFBM    [[texture(7)]]  — 1024² RGBA FBM          (.rgba8Unorm)
        //   texture2d<float>  blueNoise   [[texture(8)]]  — 256²  IGN dither        (.r8Unorm)
        //
        // ── IBL textures (Increment 3.16) ────────────────────────────────────
        // IBLManager binds IBL textures at [[texture(9)]]–[[texture(11)]].
        // These are sampled by the fixed raymarch_lighting_fragment in the Renderer library;
        // preset G-buffer shaders do not need to declare them directly.
        // For reference (custom lighting in advanced presets):
        //
        //   texturecube<float> iblIrradiance  [[texture(9)]]  — 32²  irradiance cubemap (.rgba16Float)
        //   texturecube<float> iblPrefiltered [[texture(10)]] — 128² prefiltered env, 5 mips (.rgba16Float)
        //   texture2d<float>   iblBRDFLUT     [[texture(11)]] — 512² BRDF split-sum LUT (.rg16Float)
        //
        // Convenience samplers — valid as file-scope constexpr in MSL:
        constexpr sampler linearSampler(filter::linear,  address::repeat);
        constexpr sampler nearestSampler(filter::nearest, address::repeat);
        constexpr sampler mipLinearSampler(filter::linear, mip_filter::linear, address::repeat);

        // HSV to RGB conversion.
        float3 hsv2rgb(float3 c) {
            float3 p = abs(fract(float3(c.x) + float3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
            return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
        }

        // ── Meshlet structures (use_mesh_shader: true presets) ─────────────────
        // Preset mesh shaders declare `mesh<MeshVertex, MeshPrimitive, N, M, ...>`
        // with N ≤ 256 (maxVerticesPerMeshlet) and M ≤ 512 (maxPrimitivesPerMeshlet).

        struct ObjectPayload {
            uint meshlet_index;
            uint vertex_offset;
            uint primitive_offset;
        };

        struct MeshVertex {
            float4 position [[position]];
            float2 uv;
            float3 normal;
        };

        struct MeshPrimitive {};
        """

        // Load ShaderUtilities.metal from the Presets bundle resource.
        let utilitiesSource: String
        if let url = Bundle.module.url(
            forResource: "ShaderUtilities",
            withExtension: "metal",
            subdirectory: "Shaders"
        ), let content = try? String(contentsOf: url, encoding: .utf8) {
            utilitiesSource = content
            preambleLogger.info("Loaded ShaderUtilities.metal (\(content.count) chars)")
        } else {
            utilitiesSource = "// WARNING: ShaderUtilities.metal not found in bundle"
            preambleLogger.warning("ShaderUtilities.metal not found in Presets bundle")
        }

        return structPreamble + "\n\n" + utilitiesSource
    }()

    // MARK: - MV-Warp Preamble (MV-2, D-027)

    /// Additional Metal preamble injected when compiling a preset that declares `mv_warp`
    /// in its passes array.
    ///
    /// Contains:
    /// - `MVWarpPerFrame` struct — per-frame warp parameters returned by the preset function.
    /// - `WarpVertexOut` struct — vertex → fragment IO carrying warped UV and decay.
    /// - Forward declarations for preset-defined `mvWarpPerFrame()` and `mvWarpPerVertex()`.
    /// - `mvWarp_vertex` — the 32×24 vertex-grid shader that calls the preset functions.
    /// - `mvWarp_fragment` — samples the previous warp texture at the warped UV × decay.
    /// - `mvWarp_compose_fragment` — additively composites the current scene onto the warp.
    /// - `mvWarp_blit_fragment` — copies the composed warp texture to the drawable.
    ///
    /// Compiled per-preset alongside `sceneSDF`/`sceneMaterial` so that `mvWarp_vertex`
    /// can call the preset's `mvWarpPerFrame` and `mvWarpPerVertex` implementations.
    static let mvWarpPreamble: String = """

    // ── MVWarp preamble (MV-2, D-027) ────────────────────────────────────────
    // Injected only when "mv_warp" is in the preset's passes array.
    // The preset's .metal file must implement mvWarpPerFrame and mvWarpPerVertex.

    // SceneUniforms — defined here for direct (non-ray-march) mv_warp presets.
    // For ray-march mv_warp presets, rayMarchGBufferPreamble defines it first and
    // sets the guard, so this block is skipped to avoid redefinition errors.
    #ifndef SCENE_UNIFORMS_DEFINED
    #define SCENE_UNIFORMS_DEFINED
    struct SceneUniforms {
        float4 cameraOriginAndFov;        // xyz = camera pos, w = fov (radians)
        float4 cameraForward;             // xyz = forward dir, w = 0
        float4 cameraRight;               // xyz = right dir, w = 0
        float4 cameraUp;                  // xyz = up dir, w = 0
        float4 lightPositionAndIntensity; // xyz = light pos, w = intensity
        float4 lightColor;                // xyz = linear RGB, w = 0
        float4 sceneParamsA;              // x=audioTime, y=aspectRatio, z=near, w=far
        float4 sceneParamsB;              // x=fogNear, y=fogFar, zw=reserved
    };
    #endif

    // Per-frame warp parameters returned by the preset's mvWarpPerFrame().
    // All presets in the mv_warp family fill this struct; the vertex shader applies it.
    struct MVWarpPerFrame {
        float zoom;   // multiplicative zoom (1.0 = no change; >1 = zoom in)
        float rot;    // rotation in radians added to the warp grid this frame
        float decay;  // feedback blend weight [0,1] (0.96 = long trails, 0.85 = short)
        float warp;   // global warp-ripple amplitude
        float cx;     // warp centre X offset from screen centre (UV units, 0 = centre)
        float cy;     // warp centre Y offset from screen centre (UV units, 0 = centre)
        float dx;     // per-frame UV X translation
        float dy;     // per-frame UV Y translation
        float sx;     // per-axis scale correction X
        float sy;     // per-axis scale correction Y
        // Preset q-variables — pass per-frame audio data to mvWarpPerVertex.
        float q1; float q2; float q3; float q4;
        float q5; float q6; float q7; float q8;
    };

    // Vertex → fragment IO for the warp pass.
    struct WarpVertexOut {
        float4 position  [[position]]; // NDC screen position
        float2 uv;                     // direct screen UV [0,1]
        float2 warped_uv;              // displaced UV to sample prev frame at
        float  decay;                  // pf.decay, interpolated across the grid
    };

    // ── Sampler for warp texture reads (clamp-to-edge to avoid border wrap) ──
    constexpr sampler warpSampler(filter::linear, address::clamp_to_edge);

    // ── Per-preset forward declarations ──────────────────────────────────────
    // The preset .metal file MUST define both of these functions.

    /// Returns per-frame baseline warp parameters from live audio features.
    /// Called once per frame from `mvWarp_vertex` for every vertex in the grid.
    MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                                  constant StemFeatures&  stems,
                                  constant SceneUniforms& s);

    /// Per-vertex UV displacement on top of the baseline rotation/zoom/translation.
    /// `uv`  — this vertex's screen UV [0,1].
    /// `rad` — radial distance from the warp centre (0 at centre, ~1 at corners).
    /// `ang` — polar angle from the warp centre (atan2).
    /// Returns the warped UV to sample the previous frame at.
    float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                           thread const MVWarpPerFrame& pf,
                           constant FeatureVector& f,
                           constant StemFeatures& stems);

    // ── mvWarp_vertex ─────────────────────────────────────────────────────────
    // 32×24 vertex grid (31×23 quads = 1426 triangles = 4278 vertices, triangle list).
    // Each vertex computes a per-vertex warped UV by calling the preset functions.
    // Buffer layout (matches engine convention):
    //   buffer(0) = FeatureVector
    //   buffer(1) = StemFeatures
    //   buffer(2) = SceneUniforms (optional per-preset use in mvWarpPerFrame)
    vertex WarpVertexOut mvWarp_vertex(
        uint                    vid      [[vertex_id]],
        constant FeatureVector& features [[buffer(0)]],
        constant StemFeatures&  stems    [[buffer(1)]],
        constant SceneUniforms& scene    [[buffer(2)]]
    ) {
        // Reconstruct grid cell + corner from vertex id.
        // 6 vertices per quad (triangle list):
        //   0:(0,0) 1:(1,0) 2:(0,1)   3:(1,0) 4:(1,1) 5:(0,1)
        const uint2 qoffsets[6] = {
            {0,0},{1,0},{0,1}, {1,0},{1,1},{0,1}
        };
        uint quad_idx    = vid / 6;
        uint vert_in_quad = vid % 6;
        uint col = quad_idx % 31;  // 0..30 (31 quads wide)
        uint row = quad_idx / 31;  // 0..22 (23 quads tall)
        uint2 corner = uint2(col, row) + qoffsets[vert_in_quad];

        // UV: corner / (32 vertices - 1) gives exact 0..1 range.
        float2 uv = float2(float(corner.x) / 31.0,
                           float(corner.y) / 23.0);

        // Per-frame parameters from the preset (same for all vertices in this draw call).
        MVWarpPerFrame pf = mvWarpPerFrame(features, stems, scene);

        // Warp centre in UV space.
        float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
        float2 p      = uv - centre;
        float  rad    = length(p) * 2.0;
        float  ang    = atan2(p.y, p.x);

        // Per-vertex warped UV (preset defines the shape of the warp field).
        float2 warped_uv = mvWarpPerVertex(uv, rad, ang, pf, features, stems);

        // Screen position: UV → NDC (flip Y for Metal top-left origin).
        float4 ndcPos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);

        WarpVertexOut out;
        out.position  = ndcPos;
        out.uv        = uv;
        out.warped_uv = warped_uv;
        out.decay     = pf.decay;
        return out;
    }

    // ── mvWarp_fragment ───────────────────────────────────────────────────────
    // Samples the previous warp texture at the per-vertex warped UV, scaled by decay.
    // Writes to the compose texture; the compose pass then adds the current scene.
    fragment float4 mvWarp_fragment(
        WarpVertexOut      in      [[stage_in]],
        texture2d<float>   prevTex [[texture(0)]]
    ) {
        float4 prev = prevTex.sample(warpSampler, in.warped_uv);
        return prev * in.decay;
    }

    // ── mvWarp_compose_fragment ───────────────────────────────────────────────
    // Composites the current scene onto the (already decay-warped) compose texture.
    // Uses alpha-blend blending: alpha = (1 - decay) so steady-state = scene × 1.0.
    // The compose render pass uses sourceAlpha × src + one × dst blend mode.
    fragment float4 mvWarp_compose_fragment(
        VertexOut          in       [[stage_in]],
        texture2d<float>   sceneTex [[texture(0)]],
        constant float&    decay    [[buffer(0)]]
    ) {
        float4 scene = sceneTex.sample(linearSampler, in.uv);
        return float4(scene.rgb, 1.0 - decay);  // alpha drives the blend equation
    }

    // ── mvWarp_blit_fragment ──────────────────────────────────────────────────
    // Copies the composed warp texture to the drawable. No tone-mapping here —
    // the scene was already ACES-composited before entering the warp pipeline.
    fragment float4 mvWarp_blit_fragment(
        VertexOut          in      [[stage_in]],
        texture2d<float>   warpTex [[texture(0)]]
    ) {
        return warpTex.sample(warpSampler, in.uv);
    }

    """

    // MARK: - Ray March G-buffer Preamble

    /// Additional shader preamble prepended only when compiling ray march presets.
    ///
    /// Contains `SceneUniforms`, `GBufferOutput`, forward declarations for
    /// `sceneSDF`/`sceneMaterial`, and the full `raymarch_gbuffer_fragment` function.
    ///
    /// This is kept separate from `shaderPreamble` because `raymarch_gbuffer_fragment`
    /// calls the preset-defined `sceneSDF` and `sceneMaterial` functions which are
    /// undefined in standard (non-ray-march) presets.  Including it in the shared
    /// preamble would cause "symbol(s) not found" errors for all non-ray-march presets.
    static let rayMarchGBufferPreamble: String = {
        // rayMarchPreamble is embedded here (copied from the shaderPreamble closure)
        // so it can be accessed independently without recomputing shaderPreamble.
        return """


        // Guard against redefinition when mv_warp and ray_march passes are both active.
        #ifndef SCENE_UNIFORMS_DEFINED
        #define SCENE_UNIFORMS_DEFINED
        struct SceneUniforms {
            float4 cameraOriginAndFov;        // xyz = camera pos, w = fov (radians)
            float4 cameraForward;             // xyz = forward direction, w = 0
            float4 cameraRight;               // xyz = right direction, w = 0
            float4 cameraUp;                  // xyz = up direction, w = 0
            float4 lightPositionAndIntensity; // xyz = light pos, w = intensity
            float4 lightColor;                // xyz = linear RGB, w = 0
            float4 sceneParamsA;              // x=audioTime, y=aspectRatio, z=near, w=far
            float4 sceneParamsB;              // x=fogNear, y=fogFar, zw=reserved
        };
        #endif

        // G-buffer output for ray march presets.
        //   color(0)  .rg16Float    R = depth_normalized [0..1), 1.0 = sky; G = unused
        //   color(1)  .rgba8Snorm   RGB = world-space normal [-1..1]; A = ambient occlusion
        //   color(2)  .rgba8Unorm   RGB = albedo [0..1]; A = packed roughness(upper4b)+metallic(lower4b)
        struct GBufferOutput {
            float4 gbuf0 [[color(0)]];
            float4 gbuf1 [[color(1)]];
            float4 gbuf2 [[color(2)]];
        };

        // ── Per-preset forward declarations ──────────────────────────────────
        // Ray march presets must define these two functions.
        //
        // `stems` is the StemFeatures struct bound at buffer(3), containing
        // per-stem energy/band/beat values (vocals, drums, bass, other).
        // Presets should apply the D-019 warmup fallback when reading stems —
        // smoothstep(0.02, 0.06, totalStemEnergy) mixes between FeatureVector
        // proxies and true stem values so the preset behaves correctly before
        // stem separation has completed on the first chunk.
        float sceneSDF(float3 p,
                       constant FeatureVector& f,
                       constant SceneUniforms& s,
                       constant StemFeatures& stems);

        void sceneMaterial(float3 p,
                           int matID,
                           constant FeatureVector& f,
                           constant SceneUniforms& s,
                           constant StemFeatures& stems,
                           thread float3& albedo,
                           thread float& roughness,
                           thread float& metallic);

        // ── G-buffer fragment (compiled per-preset with sceneSDF + sceneMaterial) ──
        fragment GBufferOutput raymarch_gbuffer_fragment(
            VertexOut               in       [[stage_in]],
            constant FeatureVector& features [[buffer(0)]],
            constant float*         fftData  [[buffer(1)]],
            constant float*         waveform [[buffer(2)]],
            constant StemFeatures&  stems    [[buffer(3)]],
            constant SceneUniforms& scene    [[buffer(4)]],
            texture2d<float> noiseLQ     [[texture(4)]],
            texture2d<float> noiseHQ     [[texture(5)]],
            texture3d<float> noiseVolume [[texture(6)]],
            texture2d<float> noiseFBM    [[texture(7)]],
            texture2d<float> blueNoise   [[texture(8)]]
        ) {
            GBufferOutput out;

            // ── Reconstruct camera ray ───────────────────────────────────────
            float2 uv  = in.uv;
            float2 ndc = uv * 2.0 - 1.0;

            float aspectRatio = scene.sceneParamsA.y;
            float yFov        = tan(scene.cameraOriginAndFov.w * 0.5);
            float xFov        = yFov * aspectRatio;

            float3 camPos = scene.cameraOriginAndFov.xyz;
            float3 camFwd = scene.cameraForward.xyz;
            float3 camRt  = scene.cameraRight.xyz;
            float3 camUp  = scene.cameraUp.xyz;

            // Negate ndc.y: uv.y=0 is top of screen; positive Y-world = up.
            float3 rayDir = normalize(camFwd + ndc.x * xFov * camRt - ndc.y * yFov * camUp);

            // ── Ray march ───────────────────────────────────────────────────
            float nearPlane = scene.sceneParamsA.z;
            float farPlane  = scene.sceneParamsA.w;
            float t         = nearPlane;
            bool  hit       = false;

            for (int i = 0; i < 128 && t < farPlane; i++) {
                float3 p = camPos + rayDir * t;
                float  d = sceneSDF(p, features, scene, stems);
                if (d < 0.001 * t) {
                    hit = true;
                    break;
                }
                t += max(d, 0.002);
            }

            if (!hit) {
                // Sky / miss — depth = 1.0 signals no geometry to the lighting pass.
                out.gbuf0 = float4(1.0, 0.0, 0.0, 0.0);
                out.gbuf1 = float4(0.0, 0.0, 0.0, 1.0);
                out.gbuf2 = float4(0.0, 0.0, 0.0, 0.0);
                return out;
            }

            float3 hitPos = camPos + rayDir * t;

            // ── Central-differences normal ───────────────────────────────────
            const float eps = 0.001;
            float3 normal = normalize(float3(
                sceneSDF(hitPos + float3(eps, 0, 0), features, scene, stems)
              - sceneSDF(hitPos - float3(eps, 0, 0), features, scene, stems),
                sceneSDF(hitPos + float3(0, eps, 0), features, scene, stems)
              - sceneSDF(hitPos - float3(0, eps, 0), features, scene, stems),
                sceneSDF(hitPos + float3(0, 0, eps), features, scene, stems)
              - sceneSDF(hitPos - float3(0, 0, eps), features, scene, stems)
            ));

            // ── Ambient occlusion (5-sample cone) ───────────────────────────
            float ao     = 1.0;
            float aoStep = 0.15;
            for (int k = 1; k <= 5; k++) {
                float aoT   = float(k) * aoStep;
                float3 aoPos = hitPos + normal * aoT;
                float aoD   = sceneSDF(aoPos, features, scene, stems);
                ao -= max(0.0, (aoT - aoD) / aoT) * 0.2;
            }
            ao = clamp(ao, 0.0, 1.0);

            // ── Material ────────────────────────────────────────────────────
            float3 albedo    = float3(0.7);
            float  roughness = 0.5;
            float  metallic  = 0.0;
            sceneMaterial(hitPos, 0, features, scene, stems, albedo, roughness, metallic);

            // Pack roughness + metallic into 8 bits (upper 4b + lower 4b) → [0,1].
            int    rByte = int(clamp(roughness, 0.0, 1.0) * 15.0 + 0.5);
            int    mByte = int(clamp(metallic,  0.0, 1.0) * 15.0 + 0.5);
            float  packed = float((rByte << 4) | mByte) / 255.0;

            float depthNorm = clamp(t / farPlane, 0.0, 0.9999);

            out.gbuf0 = float4(depthNorm, 0.0, 0.0, 0.0);
            out.gbuf1 = float4(normal, ao);               // rgba8Snorm: [-1..1]
            out.gbuf2 = float4(albedo, packed);            // rgba8Unorm: [0..1]

            return out;
        }

        """
    }()
}
