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

        // Matches Swift FeatureVector layout (24 floats = 96 bytes).
        struct FeatureVector {
            float bass, mid, treble;
            float bass_att, mid_att, treb_att;
            float sub_bass, low_bass, low_mid, mid_high, high_mid, high_freq;
            float beat_bass, beat_mid, beat_treble, beat_composite;
            float spectral_centroid, spectral_flux;
            float valence, arousal;
            float time, delta_time;
            float _pad0, aspect_ratio;
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
        // Matches Swift StemFeatures layout (16 floats = 64 bytes).
        struct StemFeatures {
            float vocals_energy;   float vocals_band0;
            float vocals_band1;    float vocals_beat;

            float drums_energy;    float drums_band0;
            float drums_band1;     float drums_beat;

            float bass_energy;     float bass_band0;
            float bass_band1;      float bass_beat;

            float other_energy;    float other_band0;
            float other_band1;     float other_beat;
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

        struct SceneUniforms {
            float4 cameraOriginAndFov;       // xyz = camera pos, w = fov (radians)
            float4 cameraForward;            // xyz = forward direction, w = 0
            float4 cameraRight;              // xyz = right direction, w = 0
            float4 cameraUp;                 // xyz = up direction, w = 0
            float4 lightPositionAndIntensity; // xyz = light pos, w = intensity
            float4 lightColor;               // xyz = linear RGB, w = 0
            float4 sceneParamsA;             // x=audioTime, y=aspectRatio, z=near, w=far
            float4 sceneParamsB;             // x=fogNear, y=fogFar, zw=reserved
        };

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
        float sceneSDF(float3 p,
                       constant FeatureVector& f,
                       constant SceneUniforms& s);

        void sceneMaterial(float3 p,
                           int matID,
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
                float  d = sceneSDF(p, features, scene);
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
                sceneSDF(hitPos + float3(eps, 0, 0), features, scene)
              - sceneSDF(hitPos - float3(eps, 0, 0), features, scene),
                sceneSDF(hitPos + float3(0, eps, 0), features, scene)
              - sceneSDF(hitPos - float3(0, eps, 0), features, scene),
                sceneSDF(hitPos + float3(0, 0, eps), features, scene)
              - sceneSDF(hitPos - float3(0, 0, eps), features, scene)
            ));

            // ── Ambient occlusion (5-sample cone) ───────────────────────────
            float ao     = 1.0;
            float aoStep = 0.15;
            for (int k = 1; k <= 5; k++) {
                float aoT   = float(k) * aoStep;
                float3 aoPos = hitPos + normal * aoT;
                float aoD   = sceneSDF(aoPos, features, scene);
                ao -= max(0.0, (aoT - aoD) / aoT) * 0.2;
            }
            ao = clamp(ao, 0.0, 1.0);

            // ── Material ────────────────────────────────────────────────────
            float3 albedo    = float3(0.7);
            float  roughness = 0.5;
            float  metallic  = 0.0;
            sceneMaterial(hitPos, 0, albedo, roughness, metallic);

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
