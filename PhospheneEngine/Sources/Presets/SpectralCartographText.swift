// SpectralCartographText — Typographic text layout for the Spectral Cartograph dashboard.
//
// Draws all text labels for the four-panel MIR diagnostic visualisation using
// Core Text + Core Graphics. Called once per frame from DynamicTextOverlay.refresh(_:).
//
// DynamicTextOverlay applies a permanent CTM flip (translateBy+scaleBy) so the
// user coordinate space is top-down (y=0 = screen top) matching Metal UV convention.
// Positions are specified in Metal-UV terms [0..1] and converted to CG pixels
// via metalToCG(mx, my). No Y-flip needed in either metalToCG or the Metal shader.
//
// Panel layout (matches SpectralCartograph.metal):
//   TL [0,0.5]×[0,0.5]  — FFT SPECTRUM
//   TR [0.5,1]×[0,0.5]  — BAND DEVIATION
//   BL [0,0.5]×[0.5,1]  — VALENCE / AROUSAL
//   BR [0.5,1]×[0.5,1]  — TIMESERIES
//   Center               — beat orb + BPM + lock state
//
// Text elements:
//   • Panel header labels  (SF Mono Semibold 15pt)
//   • TR row labels (BASS / MID / TREBLE)  (SF Mono Regular 11pt)
//   • TR axis tick labels (–1 / 0 / +1)   (SF Mono Regular 9pt)
//   • BL axis labels + quadrant hints      (SF Mono Regular 9pt)
//   • BR row labels (BEAT φ / BASS DEV / BAR φ)   (SF Mono Regular 11pt)
//   • BR time axis (← 8s … now →)          (SF Mono Regular 9pt)
//   • BPM number (SF Mono Bold 32pt)
//   • Lock-state string (SF Mono Regular 13pt, colour-coded)

import CoreGraphics
import CoreText
import Foundation

// MARK: - SpectralCartographText

/// Pure-static text layout for the Spectral Cartograph diagnostic dashboard.
///
/// All methods are `static`; no instance state. Pass per-frame values
/// (`bpm`, `lockState`) in `draw(in:size:bpm:lockState:)`.
public enum SpectralCartographText {

    // MARK: - Entry point

    /// Draw all typographic labels for one frame of the Spectral Cartograph dashboard.
    ///
    /// - Parameters:
    ///   - ctx:       CGContext backed by DynamicTextOverlay (bottom-left origin).
    ///   - size:      Canvas dimensions (2 048 × 1 024 by default).
    ///   - bpm:       Current BPM from the SpectralHistoryBuffer (0 = no grid).
    ///   - lockState: Drift-tracker lock state: 0 = reactive, 1 = locking, 2 = locked.
    public static func draw(in ctx: CGContext, size: CGSize, bpm: Float, lockState: Int) {
        ctx.textMatrix = .identity

        let w = size.width   // 2048
        let h = size.height  // 1024

        // ── Panel header labels ───────────────────────────────────────────────────
        //
        // kHeaderH = 0.12 of panel content area.  Panel content in Metal UV space is
        // approximately Y ∈ [0.015, 0.485] for the top half (before subtracting header).
        // Header centre Metal Y ≈ 0.015 + 0.12*0.47*0.5 ≈ 0.043.  Convert to CG Y and
        // offset so the font baseline sits near the middle of the header strip.
        //
        // Top panels (Metal Y ∈ [0, 0.5]) → CG Y ∈ [512, 1024]
        // Header in top panels:
        //   Metal Y_center ≈ 0.043  →  CG Y = (1–0.043)*1024 ≈ 959
        //   Baseline (account for cap height ~12px for 15pt font): CG Y ≈ 956
        let headerFont  = ctFont("SFMono-Semibold", size: 15)
        let headerColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

        drawLabel("FFT SPECTRUM",       at: metalToCG(0.012, 0.036, w, h), font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("BAND DEVIATION",     at: metalToCG(0.512, 0.036, w, h), font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("VALENCE / AROUSAL",  at: metalToCG(0.012, 0.536, w, h), font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("TIMESERIES  8 s",    at: metalToCG(0.512, 0.536, w, h), font: headerFont, color: headerColor, ctx: ctx)

        // ── TR: band row labels and axis ticks ────────────────────────────────────
        //
        // drawBandDeviation divides content Y [0,1] into three equal rows.
        // Content area (excl header) in TR Metal UV: X ∈ [0.515, 0.985], Y ∈ [0.068, 0.48]
        // Row centres in Metal Y: 0.068 + [0.137, 0.274, 0.411]
        let rowFont  = ctFont("SFMono-Regular", size: 11)
        let rowDim   = CGColor(red: 0.68, green: 0.68, blue: 0.68, alpha: 1)
        let tickFont = ctFont("SFMono-Regular", size: 9)
        let tickDim  = CGColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1)

        // Row labels — left edge of TR panel, row-centre Y
        let trLabelX: Double = 0.513
        drawLabel("BASS",   at: metalToCG(trLabelX, 0.196, w, h), font: rowFont, color: rowDim, ctx: ctx)
        drawLabel("MID",    at: metalToCG(trLabelX, 0.333, w, h), font: rowFont, color: rowDim, ctx: ctx)
        drawLabel("TREBLE", at: metalToCG(trLabelX, 0.470, w, h), font: rowFont, color: rowDim, ctx: ctx)

        // Axis tick labels for row 0 (shown once at top — same for all three rows).
        // The bar's zero centre is at UV X=0.5; left/right extremes ≈ 0.535/0.975
        drawLabel("–1", at: metalToCG(0.532, 0.060, w, h), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("0",  at: metalToCG(0.740, 0.060, w, h), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("+1", at: metalToCG(0.960, 0.060, w, h), font: tickFont, color: tickDim, ctx: ctx)

        // ── BL: valence/arousal axis labels + quadrant hints ──────────────────────
        //
        // The phase plot maps UV X→valence (−1..+1) and UV Y→arousal (−1..+1, inverted).
        // Content area (excl header): X ∈ [0.015, 0.485], Y ∈ [0.568, 0.98]
        // Axes cross at (0.25, 0.775) in Metal UV.
        let axFont = ctFont("SFMono-Regular", size: 9)
        let axDim  = CGColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1)
        let qdFont = ctFont("SFMono-Regular", size: 8)
        let qdDim  = CGColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1)

        // Valence axis labels (horizontal, below plot)
        drawLabel("–1 NEGATIVE",  at: metalToCG(0.015, 0.975, w, h), font: axFont, color: axDim, ctx: ctx)
        drawLabel("POSITIVE +1",  at: metalToCG(0.370, 0.975, w, h), font: axFont, color: axDim, ctx: ctx)

        // Arousal labels (vertical extremes)
        drawLabel("HIGH",         at: metalToCG(0.015, 0.570, w, h), font: axFont, color: axDim, ctx: ctx)
        drawLabel("LOW",          at: metalToCG(0.015, 0.965, w, h), font: axFont, color: axDim, ctx: ctx)

        // Quadrant semantic hints
        drawLabel("joy",    at: metalToCG(0.390, 0.620, w, h), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("stress", at: metalToCG(0.030, 0.620, w, h), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("sad",    at: metalToCG(0.030, 0.940, w, h), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("calm",   at: metalToCG(0.390, 0.940, w, h), font: qdFont, color: qdDim, ctx: ctx)

        // ── BR: timeseries row labels + time axis ─────────────────────────────────
        //
        // Three rows (beat_phase01 / bass_dev / bar_phase01), content Y [0.068,1.0] in BR.
        // BR panel Metal UV: X ∈ [0.515, 0.985], Y ∈ [0.568, 0.980]
        // Row span ≈ 0.137 each; label placed near each row's top-left.
        let beatPhaseClr = CGColor(red: 1.0,  green: 0.784, blue: 0.341, alpha: 0.9)
        let bassDevClr   = CGColor(red: 1.0,  green: 0.361, blue: 0.361, alpha: 0.9)
        let barPhaseClr  = CGColor(red: 0.482, green: 0.361, blue: 1.0,   alpha: 0.9)

        drawLabel("BEAT φ",   at: metalToCG(0.513, 0.605, w, h), font: rowFont, color: beatPhaseClr, ctx: ctx)
        drawLabel("BASS DEV", at: metalToCG(0.513, 0.742, w, h), font: rowFont, color: bassDevClr,   ctx: ctx)
        drawLabel("BAR φ",    at: metalToCG(0.513, 0.879, w, h), font: rowFont, color: barPhaseClr,  ctx: ctx)

        // Time axis labels (bottom of BR content area)
        drawLabel("← 8 s",  at: metalToCG(0.515, 0.975, w, h), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("now →",  at: metalToCG(0.930, 0.975, w, h), font: tickFont, color: tickDim, ctx: ctx)

        // ── Beat orb: BPM + lock state ────────────────────────────────────────────
        //
        // kOrbRadius = 0.22 in viewport UV. Orb centre = (0.5, 0.5).
        // BPM sits above: Metal Y ≈ 0.5 – 0.22 – 0.06 = 0.22
        // Lock state sits below: Metal Y ≈ 0.5 + 0.22 + 0.04 = 0.76
        drawBPM(bpm, orbAboveY: 0.220, ctx: ctx, w: w, h: h)
        drawLockState(lockState, orbBelowY: 0.770, ctx: ctx, w: w, h: h)
    }

    // MARK: - BPM

    private static func drawBPM(_ bpm: Float, orbAboveY: Double, ctx: CGContext, w: CGFloat, h: CGFloat) {
        let bpmI = Int(bpm + 0.5)
        guard bpmI > 0 && bpmI < 1000 else { return }

        let bpmFont  = ctFont("SFMono-Bold", size: 32)
        let bpmColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let bpmStr   = "\(bpmI) BPM"
        let line     = ctLine(bpmStr, font: bpmFont, color: bpmColor)

        let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgPos = metalToCG(0.5 - (lineW / w) * 0.5, orbAboveY, w, h)
        ctx.textPosition = cgPos
        CTLineDraw(line, ctx)
    }

    // MARK: - Lock state

    private static func drawLockState(_ lockState: Int, orbBelowY: Double, ctx: CGContext, w: CGFloat, h: CGFloat) {
        let lockFont = ctFont("SFMono-Regular", size: 13)
        let (lockStr, lockColor): (String, CGColor) = {
            switch lockState {
            case 2:  return ("● LOCKED",   CGColor(red: 0.30, green: 1.00, blue: 0.30, alpha: 1))
            case 1:  return ("◐ LOCKING",  CGColor(red: 1.00, green: 0.85, blue: 0.20, alpha: 1))
            default: return ("○ REACTIVE", CGColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1))
            }
        }()
        let line  = ctLine(lockStr, font: lockFont, color: lockColor)
        let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgPos = metalToCG(0.5 - (lineW / w) * 0.5, orbBelowY, w, h)
        ctx.textPosition = cgPos
        CTLineDraw(line, ctx)
    }

    // MARK: - Helpers

    /// Convert Metal UV coordinates to CGContext pixels.
    ///
    /// After DynamicTextOverlay's CTM flip, user-space y=0 = screen top and y=h = screen bottom,
    /// matching Metal UV convention directly.  No Y-flip needed here.
    private static func metalToCG(_ mx: Double, _ my: Double, _ w: CGFloat, _ h: CGFloat) -> CGPoint {
        return CGPoint(x: CGFloat(mx) * w, y: CGFloat(my) * h)
    }

    /// Draw a left-aligned text label at the given CGContext position.
    private static func drawLabel(
        _ str: String,
        at point: CGPoint,
        font: CTFont,
        color: CGColor,
        ctx: CGContext
    ) {
        let line = ctLine(str, font: font, color: color)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    /// Create a CTLine from a string with the given font and colour.
    private static func ctLine(_ str: String, font: CTFont, color: CGColor) -> CTLine {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let aStr = CFAttributedStringCreate(nil, str as CFString, attrs as CFDictionary)!
        return CTLineCreateWithAttributedString(aStr)
    }

    /// Create a CTFont by PostScript name with system-font fallback.
    ///
    /// Tried names:
    ///   SFMono-Bold, SFMono-Semibold, SFMono-Regular  (SF Mono — macOS 10.12+)
    ///   Menlo-Bold, Menlo-Regular                       (safe fallback)
    ///   CourierNewPS-BoldMT, CourierNewPSMT             (last resort)
    private static func ctFont(_ name: String, size: CGFloat) -> CTFont {
        // CTFontCreateWithName returns a last-resort font when name is unavailable.
        let font = CTFontCreateWithName(name as CFString, size, nil)
        // Verify the name matched — if not, fall back to Menlo which is guaranteed on macOS.
        let actualName = CTFontCopyPostScriptName(font) as String
        if actualName.lowercased().contains("lastresort") || actualName == ".AppleLastResortFont" {
            let fallbackName = name.contains("Bold") ? "Menlo-Bold" : "Menlo-Regular"
            return CTFontCreateWithName(fallbackName as CFString, size, nil)
        }
        return font
    }
}
