// SpectralCartograph.metal — Real-time MIR diagnostic instrument preset.
//
// Four-quadrant data visualisation on black. No feedback, no warp.
// Shows the live state of MV-1 deviation primitives (D-026) and
// MV-3 extensions (D-028) in a single glanceable display.
//
// Panel layout (UV origin top-left):
//   TL [0,0.5]×[0,0.5]   — 512-bin FFT spectrum, log-frequency, centroid-driven colour
//   TR [0.5,1]×[0,0.5]   — 3-band deviation meters (att_rel signed bar + dev fill + beat tick)
//   BL [0,0.5]×[0.5,1]   — Valence/arousal phase plot, 8-second fading trail
//   BR [0.5,1]×[0.5,1]   — Scrolling line graphs: beat_phase01, bass_dev, vocal pitch
//
// Buffer bindings (direct-pass layout, actual engine convention):
//   buffer(0) = FeatureVector (192 bytes)
//   buffer(1) = FFT magnitudes (512 floats)
//   buffer(2) = waveform (unused v1)
//   buffer(3) = StemFeatures (256 bytes)
//   buffer(5) = SpectralHistory (4096 floats, 16 KB)
//
// D-026 compliance: drawBandDeviation reads only deviation primitives
//   (bass_att_rel, bass_dev, etc.) — never absolute f.bass / f.mid / f.treble.

// ── Palette ───────────────────────────────────────────────────────────────────

constant float3 kBorderColor  = float3(0.15);
constant float  kBorderWidth  = 0.002;    // ~1 px at 1080p
constant float  kPadding      = 0.015;

// TL spectrum
constant float3 kColdColor    = float3(0.0,  0.333, 0.667);  // cool blue
constant float3 kWarmColor    = float3(1.0,  0.690, 0.376);  // warm amber

// TR deviation meters
constant float3 kAxisColor    = float3(0.22);                  // centrelinecolor
constant float3 kRelColor     = float3(0.941, 0.910, 0.847);  // #F0E8D8 warm white
constant float3 kDevColor     = float3(0.482, 0.361, 1.000);  // #7B5CFF violet
constant float3 kBeatTickClr  = float3(1.0,  0.361, 0.361);  // #FF5C5C coral

// BL valence/arousal
constant float3 kVAColor      = float3(0.310, 0.820, 0.773);  // #4FD1C5 teal
constant float3 kGridColor    = float3(0.18);

// BR scrolling graphs
constant float3 kBeatPhaseClr = float3(1.0,  0.784, 0.341);  // #FFC857 amber
constant float3 kBassDevClr   = float3(1.0,  0.361, 0.361);  // #FF5C5C coral
constant float3 kPitchClr     = float3(0.482, 0.361, 1.000); // #7B5CFF violet

// ── History buffer offsets (mirror SpectralHistoryBuffer.swift) ───────────────
constant int kHistLen         = 480;
constant int kOffValence      = 0;
constant int kOffArousal      = 480;
constant int kOffBeatPhase    = 960;
constant int kOffBassDev      = 1440;
constant int kOffPitchNorm    = 1920;
constant int kOffWriteHead    = 2400;
constant int kOffSamplesValid = 2401;

// ── Panel helpers ─────────────────────────────────────────────────────────────

/// Return true if uv lands on a hairline border between two adjacent panels.
static inline bool onPanelBorder(float2 uv) {
    float dx = abs(uv.x - 0.5);
    float dy = abs(uv.y - 0.5);
    return dx < kBorderWidth || dy < kBorderWidth;
}

/// Map a panel-local UV [0,1]² into a content-area UV by stripping padding.
static inline float2 toContent(float2 panelUV) {
    return (panelUV - kPadding) / (1.0 - 2.0 * kPadding);
}

// ── TL: FFT spectrum ──────────────────────────────────────────────────────────

static inline float3 drawSpectrum(
    float2                  uv,
    constant float*         fft,
    constant FeatureVector& fv)
{
    // Log-frequency mapping — perceptually uniform low-frequency resolution.
    float binF  = pow(uv.x, 2.5) * 511.0;
    int   bin   = clamp(int(binF), 0, 511);
    int   bin1  = min(bin + 1, 511);
    float frac  = binF - float(bin);
    float mag   = mix(fft[bin], fft[bin1], frac);

    // FFT values post-AGC cluster around 0.5; scale so quiet content stays visible.
    float magN  = clamp(mag * 2.0, 0.0, 1.0);
    float barTop = 1.0 - magN;

    // spectral_centroid is pre-normalised to [0..1] by Nyquist in MIRPipeline.
    float3 barClr = mix(kColdColor, kWarmColor, clamp(fv.spectral_centroid, 0.0, 1.0));

    float inBar  = step(barTop, uv.y);
    // Subtle baseline glow so the panel isn't dark during silence.
    float base   = smoothstep(1.0, 0.97, uv.y) * 0.04;

    return barClr * inBar * magN + float3(base);
}

// ── TR: 3-band deviation meters (D-026 compliant) ────────────────────────────

static inline float3 drawBandDeviation(float2 uv, constant FeatureVector& fv) {
    float rowF   = uv.y * 3.0;
    int   row    = clamp(int(rowF), 0, 2);
    float yInRow = fract(rowF);

    // Hairline dividers between rows.
    if (row > 0 && yInRow < 0.012) return float3(0.15);

    // Per-row driver selection — ONLY deviation primitives (D-026 requirement).
    float attRel, dev, beat;
    if (row == 0) {
        attRel = fv.bass_att_rel;  dev = fv.bass_dev;  beat = fv.beat_bass;
    } else if (row == 1) {
        attRel = fv.mid_att_rel;   dev = fv.mid_dev;   beat = fv.beat_mid;
    } else {
        attRel = fv.treb_att_rel;  dev = fv.treb_dev;  beat = fv.beat_treble;
    }

    // X mapping: x=0 → rel=-1, x=0.5 → rel=0, x=1 → rel=+1.
    float centre   = 0.5;
    float relOff   = clamp(attRel, -1.0, 1.0) * 0.5;
    float relLo    = min(centre, centre + relOff);
    float relHi    = max(centre, centre + relOff);
    float devHi    = centre + clamp(dev, 0.0, 1.0) * 0.5;

    float3 color   = float3(0.0);

    // Vertical centreline.
    if (abs(uv.x - centre) < 0.003) color = kAxisColor;

    // Signed att_rel bar — narrow mid-row band.
    if (yInRow > 0.35 && yInRow < 0.55 && uv.x >= relLo && uv.x <= relHi)
        color = max(color, kRelColor * 0.85);

    // Positive dev fill — lower band, right of centre only.
    if (yInRow > 0.60 && yInRow < 0.90 && uv.x >= centre && uv.x <= devHi)
        color = max(color, kDevColor);

    // Beat tick — right-edge strip, intensity = beat pulse value.
    if (uv.x > 0.965 && yInRow > 0.08 && yInRow < 0.92)
        color = max(color, kBeatTickClr * clamp(beat, 0.0, 1.0));

    return color;
}

// ── BL: Valence/arousal phase plot ────────────────────────────────────────────

static inline float3 drawValenceArousal(
    float2                  uv,
    constant FeatureVector& fv,
    constant float*         history)
{
    // Map content UV to VA space: (0,0) centre, x=valence, y=arousal.
    float2 va = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);

    float3 color = float3(0.0);

    // Crosshair grid lines at origin.
    float crossH = 1.0 - smoothstep(0.0, 0.004, abs(va.y));
    float crossV = 1.0 - smoothstep(0.0, 0.004, abs(va.x));
    color = kGridColor * 0.5 * max(crossH, crossV);

    int writeHead    = int(history[kOffWriteHead]);
    int samplesValid = int(history[kOffSamplesValid]);

    const float kInvN = 1.0 / float(kHistLen);
    for (int age = 0; age < kHistLen; ++age) {
        if (age >= samplesValid) break;
        int   slot   = (writeHead - 1 - age + kHistLen) % kHistLen;
        float2 smp   = float2(history[kOffValence + slot], history[kOffArousal + slot]);
        float  ageN  = float(age) * kInvN;
        float  r     = mix(0.012, 0.004, ageN);
        float  fade  = (1.0 - ageN) * (1.0 - ageN);
        float  cover = 1.0 - smoothstep(0.0, r, length(va - smp));
        color = max(color, kVAColor * cover * fade);
    }

    // Live point (larger, full brightness).
    float2 live = float2(fv.valence, fv.arousal);
    float  liveA = 1.0 - smoothstep(0.0, 0.020, length(va - live));
    color = max(color, kVAColor * liveA);

    return color;
}

// ── BR: Scrolling line graphs ─────────────────────────────────────────────────

static inline float3 drawFeatureGraphs(float2 uv, constant float* history) {
    const float kRowH = 1.0 / 3.0;
    int    row;
    int    offset;
    float3 lineClr;

    if (uv.y < kRowH) {
        row = 0; offset = kOffBeatPhase; lineClr = kBeatPhaseClr;
    } else if (uv.y < 2.0 * kRowH) {
        row = 1; offset = kOffBassDev;   lineClr = kBassDevClr;
    } else {
        row = 2; offset = kOffPitchNorm; lineClr = kPitchClr;
    }
    float yInRow = fract(uv.y * 3.0);

    if (row > 0 && yInRow < 0.010) return float3(0.15);  // divider

    int writeHead    = int(history[kOffWriteHead]);
    int samplesValid = int(history[kOffSamplesValid]);

    // Map x to age: x=1 → age 0 (newest), x=0 → age kHistLen-1 (oldest).
    int age     = int((1.0 - uv.x) * float(kHistLen));
    int prevAge = age + 1;
    if (age >= samplesValid) return float3(0.0);

    int   slotC = (writeHead - 1 - age     + kHistLen) % kHistLen;
    int   slotP = (writeHead - 1 - prevAge + kHistLen) % kHistLen;
    float valC  = history[offset + slotC];
    float valP  = (prevAge >= samplesValid) ? valC : history[offset + slotP];

    const float kTopMarg    = 0.08;
    const float kBotMarg    = 0.08;
    const float kUsable     = 1.0 - kTopMarg - kBotMarg;

    float tC    = kTopMarg + (1.0 - valC) * kUsable;
    float tP    = kTopMarg + (1.0 - valP) * kUsable;
    float minT  = min(tC, tP);
    float maxT  = max(tC, tP);
    float dist  = max(0.0, max(minT - yInRow, yInRow - maxT));

    float lineA = 1.0 - smoothstep(0.0, 0.012, dist);

    // Faint 0.5 reference line.
    float midY   = kTopMarg + 0.5 * kUsable;
    float midA   = (1.0 - smoothstep(0.0, 0.003, abs(yInRow - midY))) * 0.08;

    // Pitch row: suppress line when unvoiced (pitch_norm == 0).
    if (row == 2 && valC <= 0.001 && valP <= 0.001)
        return float3(midA);

    return lineClr * lineA + float3(midA);
}

// ── Entry point ───────────────────────────────────────────────────────────────

fragment float4 spectral_cartograph_fragment(
    VertexOut               in       [[stage_in]],
    constant FeatureVector& fv       [[buffer(0)]],
    constant float*         fftBins  [[buffer(1)]],
    constant float*         waveform [[buffer(2)]],   // bound but unused v1
    constant StemFeatures&  stems    [[buffer(3)]],
    constant float*         history  [[buffer(5)]])
{
    float2 uv = in.uv;

    // Global panel border hairlines.
    if (onPanelBorder(uv)) return float4(kBorderColor, 1.0);

    // Quadrant: panelX 0=left, 1=right; panelY 0=top, 1=bottom.
    int    panelX = uv.x < 0.5 ? 0 : 1;
    int    panelY = uv.y < 0.5 ? 0 : 1;
    float2 origin = float2(float(panelX) * 0.5, float(panelY) * 0.5);
    float2 local  = (uv - origin) * 2.0;

    // Inner border per quadrant.
    float bd = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
    if (bd < kBorderWidth) return float4(kBorderColor, 1.0);

    float2 content = toContent(local);
    if (any(content < 0.0) || any(content > 1.0))
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 color;
    if      (panelX == 0 && panelY == 0) color = drawSpectrum(content, fftBins, fv);
    else if (panelX == 1 && panelY == 0) color = drawBandDeviation(content, fv);
    else if (panelX == 0 && panelY == 1) color = drawValenceArousal(content, fv, history);
    else                                 color = drawFeatureGraphs(content, history);

    return float4(color, 1.0);
}
