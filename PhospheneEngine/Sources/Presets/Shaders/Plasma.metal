// Plasma — Classic demoscene plasma effect driven by audio energy.
// Sine/cosine interference patterns modulated by FFT bands.
// Colors: time-cycling hue with frequency-dependent saturation.

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float t = features.time;

    // Compute energy from low, mid, and high frequency bands.
    float lowEnergy = 0.0;
    for (int i = 0; i < 32; i++) { lowEnergy += fftMagnitudes[i]; }
    lowEnergy = saturate(lowEnergy / 32.0 * 8.0);

    float midEnergy = 0.0;
    for (int i = 32; i < 128; i++) { midEnergy += fftMagnitudes[i]; }
    midEnergy = saturate(midEnergy / 96.0 * 8.0);

    float highEnergy = 0.0;
    for (int i = 128; i < 512; i++) { highEnergy += fftMagnitudes[i]; }
    highEnergy = saturate(highEnergy / 384.0 * 12.0);

    // Plasma field: layered sine interference.
    float2 p = (uv - 0.5) * 4.0;

    // Scale distortion by low frequency energy (bass drives the geometry).
    float scale = 1.0 + lowEnergy * 0.8;
    p *= scale;

    float v1 = sin(p.x * 1.5 + t * 0.7);
    float v2 = sin(p.y * 1.3 + t * 0.5);
    float v3 = sin((p.x + p.y) * 0.9 + t * 0.6);
    float v4 = sin(length(p + float2(sin(t * 0.3), cos(t * 0.4))) * 1.8);

    // Mid energy modulates pattern complexity.
    float plasma = (v1 + v2 + v3 + v4) * 0.25;
    plasma += sin(plasma * 3.14159 * 2.0 + midEnergy * 3.0) * 0.3;

    // Map plasma value to color.
    // Hue cycles with time and shifts with high-frequency content.
    float hue = fract(plasma * 0.5 + t * 0.05 + highEnergy * 0.15);
    float saturation = 0.75 + midEnergy * 0.2;
    float brightness = 0.4 + (plasma * 0.5 + 0.5) * 0.5 + lowEnergy * 0.15;

    float3 color = hsv2rgb(float3(hue, saturation, brightness));

    // Subtle radial darkening from edges.
    float vignette = 1.0 - length(uv - 0.5) * 0.6;
    color *= vignette;

    color = min(color, float3(1.0));
    return float4(color, 1.0);
}
