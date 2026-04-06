// Waveform.metal — First-light visualizer: frequency bar spectrum + oscilloscope waveform.
// Reads FFT magnitude buffer (512 bins) and PCM waveform ring buffer directly on the GPU.
// Colors follow Phosphene's philosophy: rich, saturated palettes emerging from darkness.

#include <metal_stdlib>
using namespace metal;

#define FFT_BIN_COUNT 512
#define WAVEFORM_CAPACITY 2048  // Interleaved stereo float32 (1024 frames)

// Matches Swift FeatureVector layout (24 floats = 96 bytes).
struct FeatureVector {
    float bass, mid, treble;
    float bass_att, mid_att, treb_att;
    float sub_bass, low_bass, low_mid, mid_high, high_mid, high_freq;
    float beat_bass, beat_mid, beat_treble, beat_composite;
    float spectral_centroid, spectral_flux;
    float valence, arousal;
    float time, delta_time;
    float _pad0, _pad1;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Vertex Shader

// Full-screen triangle: 3 vertices, no vertex buffer needed.
// The oversized triangle is clipped by the rasterizer to the viewport.
vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    VertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    // Flip Y so uv (0,0) = bottom-left, (1,1) = top-right.
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// MARK: - Color Utilities

float3 hsv2rgb(float3 c) {
    float3 p = abs(fract(float3(c.x) + float3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// MARK: - Fragment Shader

fragment float4 waveform_fragment(VertexOut in [[stage_in]],
                                  constant FeatureVector& features [[buffer(0)]],
                                  constant float* fftMagnitudes [[buffer(1)]],
                                  constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float3 color = float3(0.0);

    // Compute total energy for global brightness modulation.
    float totalEnergy = 0.0;
    for (int i = 0; i < FFT_BIN_COUNT; i++) {
        totalEnergy += fftMagnitudes[i];
    }
    totalEnergy = saturate(totalEnergy / float(FFT_BIN_COUNT) * 12.0);

    // ═══════════════════════════════════════════════════════════════
    // SPECTRUM ANALYZER — bottom 55% of screen
    // 512 bins grouped into 64 bars, growing upward from the bottom.
    // ═══════════════════════════════════════════════════════════════

    constexpr int NUM_BARS = 64;
    constexpr int BINS_PER_BAR = FFT_BIN_COUNT / NUM_BARS;  // 8

    float barIndexF = uv.x * float(NUM_BARS);
    int bar = clamp(int(barIndexF), 0, NUM_BARS - 1);
    float barFrac = fract(barIndexF);

    // Inter-bar gap for visual separation.
    float barMask = smoothstep(0.0, 0.1, barFrac) * smoothstep(1.0, 0.9, barFrac);

    // Peak magnitude within this bar's bin group.
    float barMag = 0.0;
    int startBin = bar * BINS_PER_BAR;
    for (int i = 0; i < BINS_PER_BAR; i++) {
        barMag = max(barMag, fftMagnitudes[startBin + i]);
    }

    // Boost magnitudes — raw FFT values are small.
    barMag = saturate(barMag * 10.0);

    float barHeight = barMag * 0.55;

    // Bars from the bottom.
    if (uv.y < barHeight) {
        // Hue: purple (low freq) → blue → cyan → green (high freq).
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        float saturation = 0.85;

        // Brighter at bar top, darker at base.
        float vertGrad = uv.y / max(barHeight, 0.001);
        float brightness = (barMag * 0.7 + 0.3) * mix(0.35, 1.0, vertGrad);

        color += hsv2rgb(float3(hue, saturation, brightness)) * barMask;
    }

    // Soft glow above bar tops.
    if (uv.y >= barHeight && uv.y < barHeight + 0.06) {
        float d = (uv.y - barHeight) / 0.06;
        float glow = exp(-d * 5.0) * barMag * 0.25;
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        color += hsv2rgb(float3(hue, 0.5, glow)) * barMask;
    }

    // ═══════════════════════════════════════════════════════════════
    // MIRRORED REFLECTION — top, faded and shorter
    // ═══════════════════════════════════════════════════════════════

    float mirrorY = 1.0 - uv.y;
    float mirrorHeight = barHeight * 0.35;
    if (mirrorY < mirrorHeight) {
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        float vertGrad = mirrorY / max(mirrorHeight, 0.001);
        float brightness = barMag * 0.25 * mix(0.3, 0.8, vertGrad);
        color += hsv2rgb(float3(hue, 0.65, brightness)) * barMask * 0.35;
    }

    // ═══════════════════════════════════════════════════════════════
    // WAVEFORM OSCILLOSCOPE — centered at y = 0.72
    // Reads interleaved stereo, averages to mono for display.
    // ═══════════════════════════════════════════════════════════════

    constexpr float WAVE_CENTER = 0.72;
    constexpr float WAVE_AMPLITUDE = 0.12;
    constexpr int WAVE_FRAMES = WAVEFORM_CAPACITY / 2;  // 1024 mono frames

    // Map x position to sample frame index.
    float frameF = uv.x * float(WAVE_FRAMES - 1);
    int frame0 = clamp(int(frameF), 0, WAVE_FRAMES - 2);
    int frame1 = frame0 + 1;
    float lerp_t = fract(frameF);

    // Read interleaved stereo, average to mono.
    int idx0 = frame0 * 2;
    int idx1 = frame1 * 2;
    float sample0 = (waveformData[idx0] + waveformData[idx0 + 1]) * 0.5;
    float sample1 = (waveformData[idx1] + waveformData[idx1 + 1]) * 0.5;
    float sample = mix(sample0, sample1, lerp_t);

    float waveY = WAVE_CENTER + sample * WAVE_AMPLITUDE;

    // Anti-aliased line via distance field.
    float dist = abs(uv.y - waveY);
    float lineWidth = 0.0025;
    float lineMask = 1.0 - smoothstep(0.0, lineWidth, dist);

    // Waveform color: bright cyan with slight intensity variation.
    float3 waveColor = float3(0.3, 0.9, 1.0);
    color += waveColor * lineMask * (0.7 + 0.3 * totalEnergy);

    // Soft glow around the waveform line.
    float glowRadius = 0.015 + totalEnergy * 0.01;
    float glowMask = exp(-dist * dist / (2.0 * glowRadius * glowRadius));
    color += waveColor * glowMask * 0.12;

    // ═══════════════════════════════════════════════════════════════
    // SUBTLE CENTER LINE — reference axis for the waveform
    // ═══════════════════════════════════════════════════════════════

    float centerDist = abs(uv.y - WAVE_CENTER);
    float centerLine = 1.0 - smoothstep(0.0, 0.001, centerDist);
    color += float3(0.15, 0.2, 0.25) * centerLine * 0.4;

    // ═══════════════════════════════════════════════════════════════
    // BACKGROUND — subtle vignette, emerging from darkness
    // ═══════════════════════════════════════════════════════════════

    float2 center = float2(0.5, 0.5);
    float vignette = 1.0 - length(uv - center) * 0.4;
    color *= vignette;

    // Prevent white clipping from feedback accumulation (Phosphene rule).
    color = min(color, float3(1.0));

    return float4(color, 1.0);
}
