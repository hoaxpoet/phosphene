// Nebula — Radial frequency visualization with particle-like structure.
// FFT bins mapped radially from center, forming a circular spectrum.
// Colors: deep purples and blues for low frequencies, hot pinks and whites for highs.

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float t = features.time;
    float3 color = float3(0.0);

    // Centered coordinates.
    float2 center = uv - 0.5;
    float radius = length(center);
    float angle = atan2(center.y, center.x); // -pi to pi
    float normalizedAngle = (angle + 3.14159265) / (2.0 * 3.14159265); // 0 to 1

    // Map angle to FFT bin (full circle = 256 bins, mirrored).
    int bin = int(normalizedAngle * 256.0) % 256;
    float mag = fftMagnitudes[bin];
    float mag2 = fftMagnitudes[min(bin + 1, 511)];
    float smoothMag = mix(mag, mag2, fract(normalizedAngle * 256.0));
    smoothMag = saturate(smoothMag * 8.0);

    // Total energy for ambient glow.
    float totalEnergy = 0.0;
    for (int i = 0; i < 64; i++) { totalEnergy += fftMagnitudes[i]; }
    totalEnergy = saturate(totalEnergy / 64.0 * 6.0);

    // Radial band: frequency magnitude determines how far from center it extends.
    float bandRadius = 0.08 + smoothMag * 0.35;
    float bandWidth = 0.015 + smoothMag * 0.02;

    // Distance from the radial band edge.
    float bandDist = abs(radius - bandRadius);
    float bandMask = exp(-bandDist * bandDist / (2.0 * bandWidth * bandWidth));

    // Color: frequency-dependent hue.
    // Low bins (bass) = deep purple/blue (0.7-0.8)
    // Mid bins = cyan/green (0.4-0.5)
    // High bins = magenta/pink (0.85-0.95)
    float binNorm = float(bin) / 256.0;
    float hue = fract(0.7 + binNorm * 0.35 + t * 0.02);
    float sat = 0.7 + smoothMag * 0.2;
    float val = bandMask * (0.6 + smoothMag * 0.4);

    color += hsv2rgb(float3(hue, sat, val));

    // Inner core glow — pulses with total energy.
    float coreRadius = 0.04 + totalEnergy * 0.03;
    float coreDist = radius / coreRadius;
    float coreGlow = exp(-coreDist * coreDist * 2.0) * (0.3 + totalEnergy * 0.5);
    color += float3(0.6, 0.4, 1.0) * coreGlow;

    // Outer nebula haze — slow-rotating, energy-modulated.
    float hazeAngle = angle + t * 0.15;
    float haze = sin(hazeAngle * 3.0) * 0.5 + 0.5;
    haze *= sin(hazeAngle * 7.0 + t * 0.3) * 0.5 + 0.5;
    float hazeFade = exp(-radius * 3.0) * totalEnergy * 0.15;
    color += float3(0.3, 0.15, 0.5) * haze * hazeFade;

    // Sparkle dots at frequency peaks.
    float sparkleAngle = normalizedAngle * 64.0;
    float sparkleFrac = fract(sparkleAngle);
    float sparkleMask = smoothstep(0.45, 0.5, sparkleFrac) * smoothstep(0.55, 0.5, sparkleFrac);
    float sparkleRadius = abs(radius - bandRadius);
    sparkleMask *= exp(-sparkleRadius * sparkleRadius / 0.0004) * smoothMag;
    color += float3(1.0, 0.9, 1.0) * sparkleMask * 0.6;

    // Vignette — darker at edges.
    float vignette = 1.0 - radius * 0.8;
    color *= max(vignette, 0.0);

    color = min(color, float3(1.0));
    return float4(color, 1.0);
}
