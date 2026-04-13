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
}
