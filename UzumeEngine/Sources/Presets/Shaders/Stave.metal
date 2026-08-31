// Stave.metal — the dark ground the dispersed wave hangs in.
//
// Stave's subject is drawn entirely by `StaveTrace` from the engine's waveform buffer (see
// `Renderer/Shaders/StaveTrace.metal`). This file is ONLY the ground, and it is deliberately
// almost nothing: a near-black field with a barely-there vertical gradient, so the spectral
// curves have something to sit in without anything competing with them.
//
// It used to be much more — a ruled field, five static horizontal rules, two layers of star
// sparkles, a haze lobe and a cloud texture. All of it is gone, and the reasons are Matt's,
// from the M7 on 2026-08-16:
//
//   • the sparkles ("why the starry background — I don't think it's necessary") existed only
//     because the source render had them; they were non-reactive and carried no information;
//   • the horizontal rules existed because the preset is called Stave. A pun is not a design
//     reason, and he asked what their purpose was because they visibly had none;
//   • the vertical rules drew the beat as a line that scrolled away, so it never read as a
//     beat at all.
//
// What replaced them is the dispersion itself. Colour now means frequency, which is why the
// stem tint also went: colour cannot mean two things at once, so a stem wash would corrupt
// the one rule that makes the image legible.
//
// Silence (D-037): the ground is procedural and audio-independent, so the frame is never
// black even when the wave flattens.

fragment float4 stave_field_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    // ⚠ `fullscreen_vertex` emits TEXTURE-space uv (`out.uv.y = 1.0 - out.uv.y`), so uv.y = 0
    // is the TOP of the frame. An earlier version of this file ignored that and rendered its
    // whole gradient upside down — measured band luma ran 0.112 (top) to 0.286 (bottom)
    // against a reference's 0.175 to 0.103, and nothing caught it because a gradient is
    // plausible in either direction.
    float sky = 1.0 - in.uv.y;

    // A very slight lift toward the top, so the frame has a sense of up without becoming a
    // scene. The dispersed wave is the only thing that should draw the eye.
    float3 deep = float3(0.012, 0.013, 0.020);
    float3 upper = float3(0.026, 0.028, 0.040);
    float3 col = mix(deep, upper, sky * sky);

    return float4(col, 1.0);
}
