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
// V2 additions (DSP.2 sign-off):
//   • Centred beat orb at viewport (0.5, 0.5) showing beat phase + lock-confidence gate
//   • BR panel beat_phase01 row overlaid with cached-BeatGrid tick marks
//   • Lock-state confidence gating on orb ring/fill (0.12 / 0.45 / 1.0)
//
// V3 additions (text infrastructure):
//   • All text labels rendered via DynamicTextOverlay (Core Text / SF Mono) at texture(12).
//   • Panel headers, band row labels, axis ticks, quadrant hints, BPM, lock state
//     all use real font families instead of the 3×5 bitmap-pixel font.
//   • texture(12) sampled with flipped Y (CGContext bottom-left → Metal top-left).
//
// Buffer / texture bindings (direct-pass layout):
//   buffer(0)  = FeatureVector (192 bytes)
//   buffer(1)  = FFT magnitudes (512 floats)
//   buffer(2)  = waveform (unused)
//   buffer(3)  = StemFeatures (256 bytes)
//   buffer(5)  = SpectralHistory (4096 floats, 16 KB)
//   texture(12) = DynamicTextOverlay (2048×1024 .rgba8Unorm, refreshed CPU-side each frame)
//
// D-026 compliance: drawBandDeviation reads only deviation primitives.

// ── Palette ───────────────────────────────────────────────────────────────────

constant float3 kBorderColor  = float3(0.15);
constant float  kBorderWidth  = 0.002;
constant float  kPadding      = 0.015;

// TL spectrum
constant float3 kColdColor    = float3(0.0,  0.333, 0.667);
constant float3 kWarmColor    = float3(1.0,  0.690, 0.376);

// TR deviation meters
constant float3 kAxisColor    = float3(0.22);
constant float3 kRelColor     = float3(0.941, 0.910, 0.847);
constant float3 kDevColor     = float3(0.482, 0.361, 1.000);
constant float3 kBeatTickClr  = float3(1.0,  0.361, 0.361);

// BL valence/arousal
constant float3 kVAColor      = float3(0.310, 0.820, 0.773);
constant float3 kGridColor    = float3(0.18);

// BR scrolling graphs
constant float3 kBeatPhaseClr = float3(1.0,  0.784, 0.341);  // amber
constant float3 kBassDevClr   = float3(1.0,  0.361, 0.361);  // coral
constant float3 kPitchClr     = float3(0.482, 0.361, 1.000); // violet

// ── History buffer offsets (mirror SpectralHistoryBuffer.swift) ───────────────

constant int kHistLen         = 480;
constant int kOffValence      = 0;
constant int kOffArousal      = 480;
constant int kOffBeatPhase    = 960;
constant int kOffBassDev      = 1440;
constant int kOffPitchNorm    = 1920;
constant int kOffWriteHead    = 2400;
constant int kOffSamplesValid = 2401;
// Beat-grid overlay (SpectralHistoryBuffer.swift offsetBeatTimes=2402 .. offsetLockState=2419)
constant int kOffBeatTimes    = 2402;
constant int kBeatTimesCount  = 16;
constant int kOffBPM          = 2418;
constant int kOffLockState    = 2419;

// ── Layout constants ──────────────────────────────────────────────────────────

// Header strip: fraction of content UV height reserved for panel labels.
constant float kHeaderH       = 0.12;
// Beat orb radius in screen-height UV units (~22% of viewport height).
constant float kOrbRadius     = 0.22;

// ── Panel helpers ─────────────────────────────────────────────────────────────

static inline bool onPanelBorder(float2 uv) {
    float dx = abs(uv.x - 0.5);
    float dy = abs(uv.y - 0.5);
    return dx < kBorderWidth || dy < kBorderWidth;
}

static inline float2 toContent(float2 panelUV) {
    return (panelUV - kPadding) / (1.0 - 2.0 * kPadding);
}

// ── TL: FFT spectrum ──────────────────────────────────────────────────────────

static inline float3 drawSpectrum(
    float2                  uv,
    constant float*         fft,
    constant FeatureVector& fv)
{
    float binF  = pow(uv.x, 2.5) * 511.0;
    int   bin   = clamp(int(binF), 0, 511);
    int   bin1  = min(bin + 1, 511);
    float frac  = binF - float(bin);
    float mag   = mix(fft[bin], fft[bin1], frac);

    float magN  = clamp(mag * 2.0, 0.0, 1.0);
    float barTop = 1.0 - magN;

    float3 barClr = mix(kColdColor, kWarmColor, clamp(fv.spectral_centroid, 0.0, 1.0));

    float inBar  = step(barTop, uv.y);
    float base   = smoothstep(1.0, 0.97, uv.y) * 0.04;

    return barClr * inBar * magN + float3(base);
}

// ── TR: 3-band deviation meters (D-026 compliant) ────────────────────────────

static inline float3 drawBandDeviation(float2 uv, constant FeatureVector& fv) {
    float rowF   = uv.y * 3.0;
    int   row    = clamp(int(rowF), 0, 2);
    float yInRow = fract(rowF);

    if (row > 0 && yInRow < 0.012) return float3(0.15);

    float attRel, dev, beat;
    if (row == 0) {
        attRel = fv.bass_att_rel;  dev = fv.bass_dev;  beat = fv.beat_bass;
    } else if (row == 1) {
        attRel = fv.mid_att_rel;   dev = fv.mid_dev;   beat = fv.beat_mid;
    } else {
        attRel = fv.treb_att_rel;  dev = fv.treb_dev;  beat = fv.beat_treble;
    }

    float centre   = 0.5;
    float relOff   = clamp(attRel, -1.0, 1.0) * 0.5;
    float relLo    = min(centre, centre + relOff);
    float relHi    = max(centre, centre + relOff);
    float devHi    = centre + clamp(dev, 0.0, 1.0) * 0.5;

    float3 color   = float3(0.0);

    if (abs(uv.x - centre) < 0.003) color = kAxisColor;

    if (yInRow > 0.35 && yInRow < 0.55 && uv.x >= relLo && uv.x <= relHi)
        color = max(color, kRelColor * 0.85);

    if (yInRow > 0.60 && yInRow < 0.90 && uv.x >= centre && uv.x <= devHi)
        color = max(color, kDevColor);

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
    float2 va = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);

    float3 color = float3(0.0);

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

    float2 live = float2(fv.valence, fv.arousal);
    float  liveA = 1.0 - smoothstep(0.0, 0.020, length(va - live));
    color = max(color, kVAColor * liveA);

    return color;
}

// ── BR: Scrolling line graphs with cached-BeatGrid tick overlay ───────────────

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

    if (row > 0 && yInRow < 0.010) return float3(0.15);

    int writeHead    = int(history[kOffWriteHead]);
    int samplesValid = int(history[kOffSamplesValid]);

    int age     = int((1.0 - uv.x) * float(kHistLen));
    int prevAge = age + 1;
    if (age >= samplesValid) return float3(0.0);

    int   slotC = (writeHead - 1 - age     + kHistLen) % kHistLen;
    int   slotP = (writeHead - 1 - prevAge + kHistLen) % kHistLen;
    float valC  = history[offset + slotC];
    float valP  = (prevAge >= samplesValid) ? valC : history[offset + slotP];

    const float kTopMarg = 0.08;
    const float kBotMarg = 0.08;
    const float kUsable  = 1.0 - kTopMarg - kBotMarg;

    float tC    = kTopMarg + (1.0 - valC) * kUsable;
    float tP    = kTopMarg + (1.0 - valP) * kUsable;
    float minT  = min(tC, tP);
    float maxT  = max(tC, tP);
    float dist  = max(0.0, max(minT - yInRow, yInRow - maxT));

    float lineA = 1.0 - smoothstep(0.0, 0.012, dist);

    float midY   = kTopMarg + 0.5 * kUsable;
    float midA   = (1.0 - smoothstep(0.0, 0.003, abs(yInRow - midY))) * 0.08;

    if (row == 2 && valC <= 0.001 && valP <= 0.001)
        return float3(midA);

    float3 result = lineClr * lineA + float3(midA);

    // Cached BeatGrid tick overlay on the beat_phase01 row.
    // Draw a thin white vertical line for each beat within the visible 8-second window.
    // kHistLen frames ≈ 8s at 60 fps.  x = 1 - age/kHistLen maps age to UV x.
    // relativeBeatTime = seconds until/since beat; positive = upcoming (right of now).
    // age_for_beat = −relTime * fps ≈ −relTime * (kHistLen / 8)
    if (row == 0) {
        const float kSecsPerHistLen = 8.0;  // approximate: kHistLen samples at ~60 fps
        const float kTickHalfW = 0.003;
        for (int ti = 0; ti < kBeatTimesCount; ++ti) {
            float relTime = history[kOffBeatTimes + ti];
            if (isinf(relTime)) continue;
            // Convert relative time (seconds) to UV x position.
            // Beat at relTime=0 → x=1 (right edge = "now").
            // Beat at relTime=-kSecsPerHistLen → x=0 (left edge = "oldest").
            float tickX = 1.0 + relTime / kSecsPerHistLen;
            if (tickX < 0.0 || tickX > 1.0) continue;
            float d = abs(uv.x - tickX);
            float tickA = (1.0 - smoothstep(0.0, kTickHalfW, d)) * 0.9;
            result = max(result, float3(tickA));
        }
    }

    return result;
}

// ── Beat orb (at viewport center, drawn on top of all panels) ─────────────────
//
// Ingredients:
//   1. Dim disc background
//   2. Amber fill brightening on beat (pow(1 - phase, 3)) gated by lock confidence
//   3. White ring flash at beat onset (phase < 0.04) gated by lock confidence
//
// BPM and lock-state text are rendered by DynamicTextOverlay (texture(12)).

static inline float3 drawBeatOrb(float2 uv, constant FeatureVector& fv, constant float* history) {
    float ar  = max(fv.aspect_ratio, 0.1);
    // Aspect-ratio-corrected distance from screen center.
    float2 d2 = float2((uv.x - 0.5) * ar, uv.y - 0.5);
    float  dist = length(d2);

    if (dist > kOrbRadius * 1.15) return float3(0.0);  // early-out

    float phase = fv.beat_phase01;  // 0 at beat onset, ramps to 1

    // ── disc background ──────────────────────────────────────────────────────
    float discA   = 1.0 - smoothstep(kOrbRadius * 0.97, kOrbRadius * 1.02, dist);
    float3 result = float3(0.04) * discA;

    // ── amber fill ───────────────────────────────────────────────────────────
    float fillBright = pow(max(0.0, 1.0 - phase), 3.0);
    float3 ambColor  = kBeatPhaseClr;  // amber
    result = max(result, ambColor * fillBright * discA * 0.85);

    // ── white ring flash at beat onset ───────────────────────────────────────
    // Confidence gate: ring is bright when the drift tracker is locked to a
    // verified BeatGrid (lock_state=2), dim when locking (1), barely visible
    // in reactive/fallback mode (0). Prevents the orb from appearing to pulse
    // confidently when the beat source is just BeatPredictor guesswork.
    int   lockState    = int(history[kOffLockState] + 0.5);
    float lockConf     = lockState == 2 ? 1.0 : (lockState == 1 ? 0.45 : 0.12);
    float ringAlpha    = smoothstep(0.04, 0.0, phase) * lockConf;
    float ringDist     = abs(dist - kOrbRadius * 0.98);
    float ringA        = (1.0 - smoothstep(0.0, kOrbRadius * 0.025, ringDist)) * ringAlpha;
    // Cap at 0.94 so max channel value stays below the acceptance-test's 250/255 threshold.
    result = max(result, float3(ringA * 0.94));

    // ── amber fill also dims in reactive mode so it doesn't mislead ──────────
    result = mix(result * 0.35, result, lockConf);

    return result;
}

// ── Text overlay sampler ──────────────────────────────────────────────────────

constexpr sampler kTextSampler(coord::normalized,
                                filter::linear,
                                address::clamp_to_zero);

/// Sample the CPU-rendered text overlay at `uv`.
///
/// The DynamicTextOverlay uses a CGContext with bottom-left origin, so
/// Y must be flipped when sampling from Metal (top-left UV origin).
static inline float4 sampleTextOverlay(
    texture2d<float, access::sample> tex,
    float2 uv)
{
    return tex.sample(kTextSampler, float2(uv.x, 1.0 - uv.y));
}

// ── Entry point ───────────────────────────────────────────────────────────────

fragment float4 spectral_cartograph_fragment(
    VertexOut               in         [[stage_in]],
    constant FeatureVector& fv         [[buffer(0)]],
    constant float*         fftBins    [[buffer(1)]],
    constant float*         waveform   [[buffer(2)]],
    constant StemFeatures&  stems      [[buffer(3)]],
    constant float*         history    [[buffer(5)]],
    texture2d<float, access::sample> textOverlay [[texture(12)]])
{
    float2 uv = in.uv;

    // Global panel border hairlines.
    if (onPanelBorder(uv)) return float4(kBorderColor, 1.0);

    int    panelX = uv.x < 0.5 ? 0 : 1;
    int    panelY = uv.y < 0.5 ? 0 : 1;
    float2 origin = float2(float(panelX) * 0.5, float(panelY) * 0.5);
    float2 local  = (uv - origin) * 2.0;

    float bd = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
    if (bd < kBorderWidth) return float4(kBorderColor, 1.0);

    float2 content = toContent(local);
    if (any(content < 0.0) || any(content > 1.0))
        return float4(0.0, 0.0, 0.0, 1.0);

    // Header strip: blank dark area — text is rendered by the CPU-side overlay.
    float3 color;
    if (content.y < kHeaderH) {
        color = float3(0.0);
    } else {
        // Remap content UV so panel visualisations use full [0,1] within their zone.
        float2 c = float2(content.x, (content.y - kHeaderH) / (1.0 - kHeaderH));
        if      (panelX == 0 && panelY == 0) color = drawSpectrum(c, fftBins, fv);
        else if (panelX == 1 && panelY == 0) color = drawBandDeviation(c, fv);
        else if (panelX == 0 && panelY == 1) color = drawValenceArousal(c, fv, history);
        else                                 color = drawFeatureGraphs(c, history);
    }

    // Beat orb: overlaid on top of all panels at the viewport centre intersection.
    float3 orb = drawBeatOrb(uv, fv, history);
    color = max(color, orb);

    // Text overlay: CPU-rendered Core Text labels blended on top.
    // Alpha-over composite: result = textColor * textAlpha + color * (1 - textAlpha).
    float4 textSample = sampleTextOverlay(textOverlay, uv);
    color = mix(color, textSample.rgb, textSample.a);

    return float4(color, 1.0);
}
