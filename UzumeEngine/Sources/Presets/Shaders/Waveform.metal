// Waveform — Frequency bar spectrum + oscilloscope waveform.
// 512 FFT bins grouped into 64 bars, plus stereo PCM waveform overlay.
// Colors: purple-blue-cyan-green gradient emerging from darkness.

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float3 color = float3(0.0);

    // Total energy for global brightness modulation.
    float totalEnergy = 0.0;
    for (int i = 0; i < FFT_BIN_COUNT; i++) {
        totalEnergy += fftMagnitudes[i];
    }
    totalEnergy = saturate(totalEnergy / float(FFT_BIN_COUNT) * 12.0);

    // ── SPECTRUM ANALYZER ── bottom 55%, 64 bars ──
    constexpr int NUM_BARS = 64;
    constexpr int BINS_PER_BAR = FFT_BIN_COUNT / NUM_BARS;

    float barIndexF = uv.x * float(NUM_BARS);
    int bar = clamp(int(barIndexF), 0, NUM_BARS - 1);
    float barFrac = fract(barIndexF);
    float barMask = smoothstep(0.0, 0.1, barFrac) * smoothstep(1.0, 0.9, barFrac);

    float barMag = 0.0;
    int startBin = bar * BINS_PER_BAR;
    for (int i = 0; i < BINS_PER_BAR; i++) {
        barMag = max(barMag, fftMagnitudes[startBin + i]);
    }
    barMag = saturate(barMag * 10.0);

    float barHeight = barMag * 0.55;

    if (uv.y < barHeight) {
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        float vertGrad = uv.y / max(barHeight, 0.001);
        float brightness = (barMag * 0.7 + 0.3) * mix(0.35, 1.0, vertGrad);
        color += hsv2rgb(float3(hue, 0.85, brightness)) * barMask;
    }

    // Soft glow above bar tops.
    if (uv.y >= barHeight && uv.y < barHeight + 0.06) {
        float d = (uv.y - barHeight) / 0.06;
        float glow = exp(-d * 5.0) * barMag * 0.25;
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        color += hsv2rgb(float3(hue, 0.5, glow)) * barMask;
    }

    // ── MIRRORED REFLECTION ── top, faded ──
    float mirrorY = 1.0 - uv.y;
    float mirrorHeight = barHeight * 0.35;
    if (mirrorY < mirrorHeight) {
        float hue = float(bar) / float(NUM_BARS) * 0.45 + 0.65;
        float vertGrad = mirrorY / max(mirrorHeight, 0.001);
        float brightness = barMag * 0.25 * mix(0.3, 0.8, vertGrad);
        color += hsv2rgb(float3(hue, 0.65, brightness)) * barMask * 0.35;
    }

    // ── WAVEFORM OSCILLOSCOPE ── centered at y = 0.72 ──
    constexpr float WAVE_CENTER = 0.72;
    constexpr float WAVE_AMPLITUDE = 0.12;
    constexpr int WAVE_FRAMES = WAVEFORM_CAPACITY / 2;

    float frameF = uv.x * float(WAVE_FRAMES - 1);
    int frame0 = clamp(int(frameF), 0, WAVE_FRAMES - 2);
    int frame1 = frame0 + 1;
    float lerp_t = fract(frameF);

    int idx0 = frame0 * 2;
    int idx1 = frame1 * 2;
    float sample0 = (waveformData[idx0] + waveformData[idx0 + 1]) * 0.5;
    float sample1 = (waveformData[idx1] + waveformData[idx1 + 1]) * 0.5;
    float sample = mix(sample0, sample1, lerp_t);

    float waveY = WAVE_CENTER + sample * WAVE_AMPLITUDE;
    float dist = abs(uv.y - waveY);
    float lineWidth = 0.0025;
    float lineMask = 1.0 - smoothstep(0.0, lineWidth, dist);

    float3 waveColor = float3(0.3, 0.9, 1.0);
    color += waveColor * lineMask * (0.7 + 0.3 * totalEnergy);

    float glowRadius = 0.015 + totalEnergy * 0.01;
    float glowMask = exp(-dist * dist / (2.0 * glowRadius * glowRadius));
    color += waveColor * glowMask * 0.12;

    // ── CENTER LINE ──
    float centerDist = abs(uv.y - WAVE_CENTER);
    float centerLine = 1.0 - smoothstep(0.0, 0.001, centerDist);
    color += float3(0.15, 0.2, 0.25) * centerLine * 0.4;

    // ── VIGNETTE ──
    float vignette = 1.0 - length(uv - float2(0.5)) * 0.4;
    color *= vignette;
    color = min(color, float3(1.0));

    return float4(color, 1.0);
}
