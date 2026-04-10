// PresetLoader+Preamble — Common Metal shader preamble prepended to all presets.

// MARK: - Common Shader Preamble

extension PresetLoader {

    /// Shared Metal code prepended to every preset shader.
    /// Contains FeatureVector struct, VertexOut, fullscreen_vertex, and color utilities.
    static let shaderPreamble = """
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

    // HSV to RGB conversion.
    float3 hsv2rgb(float3 c) {
        float3 p = abs(fract(float3(c.x) + float3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
        return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }
    """
}
