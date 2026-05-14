// Common.metal — Shared definitions for all Renderer shaders.

#include <metal_stdlib>
using namespace metal;

#define FFT_BIN_COUNT 512
#define WAVEFORM_CAPACITY 2048

// MARK: - FeatureVector

// Matches Swift FeatureVector layout (48 floats = 192 bytes, MV-1/MV-3b).
// Field order is byte-identical to PresetLoader+Preamble.swift's `FeatureVector`
// so the same MTLBuffer is consumed by engine-library shaders (Particles*.metal,
// MVWarp.metal, feedback shaders) and preset shaders interchangeably. The first
// 32 floats / 128 bytes match the pre-MV-1 struct exactly; existing engine
// readers (Murmuration's `particle_update` etc.) are byte-identical.
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
    // MV-1 deviation: xRel=(x-0.5)*2 (±0.5), xDev=max(0,xRel) (D-026).
    float bass_rel, bass_dev;
    float mid_rel,  mid_dev;
    float treb_rel, treb_dev;
    float bass_att_rel, mid_att_rel, treb_att_rel;
    // MV-3b beat phase: 0 at last beat, rises to 1 at next (D-028).
    float beat_phase01, beats_until_next;
    // Bar phase: 0 at downbeat, rises to 1 at next downbeat (floats 37–38).
    float bar_phase01;
    float beats_per_bar;
    // Padding to 192 bytes (floats 39–48).
    float _pad3, _pad4, _pad5, _pad6, _pad7,
          _pad8, _pad9, _pad10, _pad11, _pad12;
};

// MARK: - FeedbackParams

struct FeedbackParams {
    float decay, base_zoom, base_rot;
    float beat_zoom, beat_rot, beat_sensitivity;
    float beat_value, _pad0;
};

// MARK: - StemFeatures

/// Per-stem audio features, bound at buffer(3) by the render pipeline.
/// Matches Swift StemFeatures layout (64 floats = 256 bytes, MV-3, D-028).
/// During warmup (~first 10s) all values are zero — apply the D-019 blend
/// `smoothstep(0.02, 0.06, totalStemEnergy)` before consuming any field.
/// First 16 floats are byte-identical to the pre-MV-3 struct so existing
/// engine readers (Murmuration's `particle_update`, MVWarp.metal) are
/// unchanged. New post-MV-1/MV-3 fields appear after byte 64.
struct StemFeatures {
    // Floats 1–16: per-stem energy/band/beat.
    float vocals_energy;      float vocals_band0;
    float vocals_band1;       float vocals_beat;

    float drums_energy;       float drums_band0;
    float drums_band1;        float drums_beat;

    float bass_energy;        float bass_band0;
    float bass_band1;         float bass_beat;

    float other_energy;       float other_band0;
    float other_band1;        float other_beat;

    // MV-1 deviation primitives (floats 17–24, D-026).
    float vocals_energy_rel;  float vocals_energy_dev;
    float drums_energy_rel;   float drums_energy_dev;
    float bass_energy_rel;    float bass_energy_dev;
    float other_energy_rel;   float other_energy_dev;

    // MV-3a rich per-stem metadata (floats 25–40, D-028).
    float vocals_onset_rate;  float vocals_centroid;
    float vocals_attack_ratio; float vocals_energy_slope;

    float drums_onset_rate;   float drums_centroid;
    float drums_attack_ratio; float drums_energy_slope;

    float bass_onset_rate;    float bass_centroid;
    float bass_attack_ratio;  float bass_energy_slope;

    float other_onset_rate;   float other_centroid;
    float other_attack_ratio; float other_energy_slope;

    // MV-3c vocal pitch (floats 41–42, D-028).
    // vocals_pitch_hz = 0 means unvoiced or confidence below 0.6.
    float vocals_pitch_hz;    float vocals_pitch_confidence;

    // Padding to 256 bytes (floats 43–64).
    float _pad1,  _pad2,  _pad3,  _pad4,  _pad5,  _pad6,  _pad7,  _pad8;
    float _pad9,  _pad10, _pad11, _pad12, _pad13, _pad14, _pad15, _pad16;
    float _pad17, _pad18, _pad19, _pad20, _pad21, _pad22;
};

// MARK: - SceneUniforms

/// Camera, lighting, and scene parameters for deferred ray march passes.
/// Bound at buffer(4) in the G-buffer and lighting passes.
/// Layout must match Swift SceneUniforms in AudioFeatures+SceneUniforms.swift.
/// All fields are float4 (16 bytes) — avoids float3 alignment ambiguity.
///
///   [0]  cameraOriginAndFov     xyz = world-space position, w = vertical fov (radians)
///   [1]  cameraForward          xyz = normalized forward direction, w = 0
///   [2]  cameraRight            xyz = normalized right direction, w = 0
///   [3]  cameraUp               xyz = normalized up direction, w = 0
///   [4]  lightPositionAndIntensity  xyz = light position, w = intensity
///   [5]  lightColor             xyz = linear RGB, w = 0
///   [6]  sceneParamsA           x=audioTime, y=aspectRatio, z=nearPlane, w=farPlane
///   [7]  sceneParamsB           x=fogNear, y=fogFar, zw=reserved
struct SceneUniforms {
    float4 cameraOriginAndFov;
    float4 cameraForward;
    float4 cameraRight;
    float4 cameraUp;
    float4 lightPositionAndIntensity;
    float4 lightColor;
    float4 sceneParamsA;
    float4 sceneParamsB;
};

// MARK: - Color Utilities

float3 hsv2rgb(float3 c) {
    float3 p = abs(fract(float3(c.x) + float3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// MARK: - Full-Screen Vertex Shader

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    VertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// MARK: - Feedback Warp Shader
//
// The feedback warp creates soft motion trails behind the flock.
// It should be ALMOST INVISIBLE as a standalone effect — its only job
// is to give the particles a gentle wake, like birds leaving vapor
// trails in cold air. The flock IS the visual. The warp just gives
// it memory.

fragment float4 feedback_warp_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant FeedbackParams& feedback [[buffer(1)]],
    texture2d<float> previousFrame [[texture(0)]],
    sampler feedbackSampler [[sampler(0)]]
) {
    float t = features.time;
    float2 uv = in.uv;

    // Very subtle offset — just enough to smear trails slightly
    // in the direction the flock is flowing. Not a psychedelic
    // zoom-and-rotate tunnel. A gentle atmospheric drag.

    float2 centered = uv - 0.5;
    float rad = length(centered);

    // Tiny inward zoom — trails shrink slightly each frame,
    // creating a "dissipation into the center" effect.
    float zoom = feedback.base_zoom * 0.3;
    centered *= 1.0 - zoom;

    // Very gentle rotation — the sky slowly turning.
    // mid_att provides a slow organic steering.
    float rot = feedback.base_rot * 0.2 * features.mid_att
              + 0.001 * sin(t * 0.2);
    float cosR = cos(rot);
    float sinR = sin(rot);
    centered = float2(centered.x * cosR - centered.y * sinR,
                      centered.x * sinR + centered.y * cosR);

    uv = centered + 0.5;

    // Sample previous frame.
    float4 prev = previousFrame.sample(feedbackSampler, uv);

    // Decay: trails fade. Higher decay = longer trails.
    // Edges fade slightly faster — keeps the center of the flock
    // as the visual anchor.
    float decay = feedback.decay - 0.01 * smoothstep(0.3, 0.5, rad);
    decay = max(decay, 0.0);

    float3 col = prev.rgb * decay;

    // Very gentle desaturation over time — prevents color buildup.
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(col, float3(lum), 0.005);

    return float4(col, prev.a * decay);
}

// MARK: - Feedback Blit Shader

fragment float4 feedback_blit_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    return tex.sample(s, in.uv);
}
