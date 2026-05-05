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
//   BR [0.5,1]×[0.5,1]   — Scrolling line graphs: beat_phase01, bass_dev, bar_phase01
//
// DSP.3.3 additions:
//   • Full-viewport beat flash: thin amber band every beat (beatPhase01 near 0).
//   • Full-viewport downbeat flash: wider white band every downbeat (barPhase01 near 0
//     and barPhase01 * beatsPerBar < 1).
//   • Beat-in-bar + beatsPerBar displayed as large text via DynamicTextOverlay.
//   • Drift in ms displayed via DynamicTextOverlay.
//   • Downbeat tick marks in BR panel (magenta, wider than beat ticks).
//   • Drift bar in BR panel row 0 header area.
//
// V2 additions (DSP.2 sign-off):
//   • Centred beat orb at viewport (0.5, 0.5) showing beat phase + lock-confidence gate
//   • BR panel beat_phase01 row overlaid with cached-BeatGrid tick marks
//   • Lock-state confidence gating on orb ring/fill (0.12 / 0.45 / 1.0)
//
// V3 additions (text infrastructure):
//   • All text labels rendered via DynamicTextOverlay (Core Text / SF Mono) at texture(12).
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
constant float3 kBeatPhaseClr  = float3(1.0,  0.784, 0.341);  // amber
constant float3 kBassDevClr    = float3(1.0,  0.361, 0.361);  // coral
constant float3 kBarPhaseClr   = float3(0.482, 0.361, 1.000); // violet

// DSP.3.3 flash colours
constant float3 kBeatFlashClr     = float3(1.0,  0.784, 0.341);  // amber beat flash
constant float3 kDownbeatFlashClr = float3(1.0,  1.0,   1.0);    // white downbeat flash
constant float3 kDownbeatTickClr  = float3(1.0,  0.4,   1.0);    // magenta downbeat ticks

// ── History buffer offsets (mirror SpectralHistoryBuffer.swift) ───────────────

constant int kHistLen         = 480;
constant int kOffValence      = 0;
constant int kOffArousal      = 480;
constant int kOffBeatPhase    = 960;
constant int kOffBassDev      = 1440;
constant int kOffBarPhase     = 1920;
constant int kOffWriteHead    = 2400;
constant int kOffSamplesValid = 2401;
// Beat-grid overlay (SpectralHistoryBuffer.swift offsetBeatTimes=2402 .. offsetLockState=2419)
constant int kOffBeatTimes     = 2402;
constant int kBeatTimesCount   = 16;
// kOffBPM = 2418 — read by SpectralHistoryBuffer.readOverlayState() for text overlay; not used in shader.
constant int kOffLockState     = 2419;
// DSP.3.1 session mode
constant int kOffSessionMode   = 2420;
// DSP.3.3 downbeat times and drift (SpectralHistoryBuffer offsets 2421..2429)
constant int kOffDownbeatTimes = 2421;
constant int kDownbeatTimesCount = 8;
constant int kOffDriftMs       = 2429;

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

// ── BR: Scrolling line graphs with beat + downbeat tick overlays ──────────────

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
        row = 2; offset = kOffBarPhase;  lineClr = kBarPhaseClr;
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

    // ── Cached BeatGrid tick overlays on the beat_phase01 row (row 0) ───────
    // Beat ticks: thin white vertical lines. Downbeat ticks: wider magenta lines.
    // Convention: relativeBeatTime = seconds until/since beat (positive = upcoming).
    // age_for_beat = −relTime × fps ≈ −relTime × (kHistLen / 8)
    if (row == 0) {
        const float kSecsPerHistLen = 8.0;

        // Beat ticks (white, half-width 0.003 UV)
        const float kBeatTickHW = 0.003;
        for (int ti = 0; ti < kBeatTimesCount; ++ti) {
            float relTime = history[kOffBeatTimes + ti];
            if (isinf(relTime)) continue;
            float tickX = 1.0 + relTime / kSecsPerHistLen;
            if (tickX < 0.0 || tickX > 1.0) continue;
            float d = abs(uv.x - tickX);
            float tickA = (1.0 - smoothstep(0.0, kBeatTickHW, d)) * 0.9;
            result = max(result, float3(tickA));
        }

        // Downbeat ticks (magenta, half-width 0.008 UV — visually wider)
        const float kDownbeatTickHW = 0.008;
        for (int di = 0; di < kDownbeatTimesCount; ++di) {
            float relTime = history[kOffDownbeatTimes + di];
            if (isinf(relTime)) continue;
            float tickX = 1.0 + relTime / kSecsPerHistLen;
            if (tickX < 0.0 || tickX > 1.0) continue;
            float d = abs(uv.x - tickX);
            float tickA = (1.0 - smoothstep(0.0, kDownbeatTickHW, d)) * 1.0;
            result = max(result, kDownbeatTickClr * tickA);
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

// ── DSP.3.3: Full-viewport beat and downbeat flash strips ─────────────────────
//
// These are unambiguous calibration aids: a thin horizontal amber band fires on
// every beat (beatPhase01 < 0.06) and a thicker white band on every downbeat
// (barPhase01 * beatsPerBar < 1 and barPhase01 < threshold).
// The flashes span the full viewport width so they are impossible to miss.
// Beat flash: top 3% of screen. Downbeat flash: top 5% of screen (wider).
// Gated by lock state — unreliable in reactive mode.

static inline float3 drawBeatFlash(
    float2                  uv,
    constant FeatureVector& fv,
    constant float*         history)
{
    int   lockState = int(history[kOffLockState] + 0.5);
    float lockConf  = lockState == 2 ? 1.0 : (lockState == 1 ? 0.5 : 0.0);
    if (lockConf < 0.01) return float3(0.0);

    float beatPhase = fv.beat_phase01;
    float barPhase  = fv.bar_phase01;
    float bpb       = max(fv.beats_per_bar, 1.0);

    // Beat-in-bar (0-indexed): 0 means downbeat.
    float beatInBarF = barPhase * bpb;
    bool  isDownbeat = (beatInBarF < 1.0);  // first beat of bar

    float3 result = float3(0.0);

    // Beat flash: thin amber strip at top 3% of viewport.
    if (uv.y < 0.030) {
        float beatA = smoothstep(0.06, 0.0, beatPhase) * lockConf;
        float stripA = smoothstep(0.030, 0.020, uv.y);  // fade at top edge
        result = max(result, kBeatFlashClr * beatA * stripA * 0.92);
    }

    // Downbeat flash: taller white strip at top 5% of viewport.
    if (uv.y < 0.050 && isDownbeat) {
        float dbA = smoothstep(0.08, 0.0, barPhase) * lockConf;
        float stripA = smoothstep(0.050, 0.030, uv.y);
        result = max(result, kDownbeatFlashClr * dbA * stripA * 0.88);
    }

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
    // No Y-flip: CGContext CTM is flipped in DynamicTextOverlay.init so memory
    // row 0 corresponds to user y=0 (top), matching Metal's UV y=0 = screen top.
    return tex.sample(kTextSampler, float2(uv.x, uv.y));
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

    // DSP.3.3: Full-viewport beat / downbeat flash strips.
    float3 flash = drawBeatFlash(uv, fv, history);
    color = max(color, flash);

    // Text overlay: CPU-rendered Core Text labels blended on top.
    // Alpha-over composite: result = textColor * textAlpha + color * (1 - textAlpha).
    float4 textSample = sampleTextOverlay(textOverlay, uv);
    color = mix(color, textSample.rgb, textSample.a);

    return float4(color, 1.0);
}
