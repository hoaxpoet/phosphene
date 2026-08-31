// StaveTrace.metal — Stave's dispersion pass: the waveform split into its spectral colours.
//
// One fullscreen draw over the band curves `StaveDispersionModel` uploads. Each band is a soft
// luminous stroke in the colour of its own frequency — 82 Hz at 662 nm deep red through to
// ~11 kHz at 404 nm violet — offset vertically by its wavelength so the spectrum physically
// separates, as a prism separates light.
//
// Additive by construction (the loop sums), then tone-mapped: where every band is present the
// frame goes toward white, exactly as mixed light does, and a sparse passage falls back to a
// few deep curves in the dark.

#include <metal_stdlib>
using namespace metal;

struct StaveUniformsGPU {
    int bandCount;
    int sampleCount;
    float thickness;
    float fan;
    float spacing;
    float zoom;
    float frameKnee;
    float pad0;
};

struct StaveDispOut {
    float4 position [[position]];
    float2 uv;
};

static_assert(sizeof(StaveUniformsGPU) == 32, "StaveUniformsGPU must stay 32 bytes");

vertex StaveDispOut stave_disp_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid & 1) ? 1.0 : -1.0, (vid >> 1) ? 1.0 : -1.0);
    StaveDispOut o;
    o.position = float4(p, 0.0, 1.0);
    // x in 0…1 across the wave window; y left in NDC so amplitudes are frame-relative.
    o.uv = float2(p.x * 0.5 + 0.5, p.y);
    return o;
}

fragment float4 stave_disp_fragment(StaveDispOut in [[stage_in]],
                                    const device float *curves [[buffer(0)]],
                                    const device float4 *colours [[buffer(1)]],
                                    constant StaveUniformsGPU &u [[buffer(2)]]) {
    float fx = in.uv.x * float(u.sampleCount - 1);
    int i0 = clamp(int(fx), 0, u.sampleCount - 1);
    int i1 = min(i0 + 1, u.sampleCount - 1);
    float frac = fx - float(i0);

    float3 col = float3(0.0);
    for (int b = 0; b < u.bandCount; ++b) {
        int base = b * u.sampleCount;
        float amp = mix(curves[base + i0], curves[base + i1], frac);

        // Dispersion. `dev` runs −1 (red, deviates least) to +1 (violet, deviates most),
        // matching the physical order: shorter wavelengths refract further. The exponent
        // weights the spread toward the red end so the bass has room to be a gesture rather
        // than competing for space with a crowded violet end.
        float tb = float(b) / float(u.bandCount - 1);
        float dev = 2.0 * pow(tb, u.spacing) - 1.0;
        // Camera zoom, then a soft ceiling at the frame edge. The knee leaves everything
        // below it untouched and folds only what would otherwise be drawn off-frame — zoom
        // alone cannot contain peaks measured at 1.53–1.98 NDC without shrinking the image
        // by 35–50 %.
        float y = (amp + u.fan * dev) * u.zoom;
        if (u.frameKnee > 0.0) {
            // PIECEWISE, not a plain tanh. A tanh through the origin compresses the whole
            // image — 12 % at mid-amplitude — which quietly shrinks the settled look. Below
            // the knee the value passes through untouched; only the excursion above it folds,
            // into the headroom that remains before the frame edge.
            float a = abs(y);
            if (a > u.frameKnee) {
                float head = 1.0 - u.frameKnee;
                a = u.frameKnee + head * tanh((a - u.frameKnee) / head);
                y = (y < 0.0) ? -a : a;
            }
        }
        float d = in.uv.y - y;

        // Two-part profile: a tight core so each band reads as a line, plus a wide halo so
        // overlapping bands ADD like light instead of sitting as separate wires. A per-band
        // thickness ramp was tried and reverted — making the low bands heavy turned the bass
        // into a soft blob and washed the summed core to white. Weight belongs to AMPLITUDE,
        // not to line width.
        float core = exp(-d * d / (u.thickness * u.thickness));
        float halo = exp(-d * d / (u.thickness * u.thickness * 36.0)) * 0.22;
        col += colours[b].rgb * (core + halo);
    }

    col = 1.0 - exp(-col * 1.35);
    // D-037: silence renders the dark ground, never black.
    col = max(col, float3(0.012, 0.013, 0.020));
    return float4(col, 1.0);
}
