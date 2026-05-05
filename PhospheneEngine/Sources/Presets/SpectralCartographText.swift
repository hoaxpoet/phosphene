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
// DynamicTextOverlay.refresh() pre-sets the text matrix to CGAffineTransform(scaleX:1,y:-1)
// to fix Core Text's horizontal mirroring in flipped coordinate systems. Do NOT reset it.
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
//   • Session-mode label (SF Mono Regular 13pt, colour-coded)
//   • Beat-in-bar counter (SF Mono Bold 28pt, below mode label) — DSP.3.3
//   • Drift readout "Δ=+12ms" (SF Mono Regular 13pt) — DSP.3.3
//   • Phase offset "+10ms" (SF Mono Regular 11pt, amber, only when non-zero) — DSP.3.3

import CoreGraphics
import CoreText
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - SpectralCartographText

/// Pure-static text layout for the Spectral Cartograph diagnostic dashboard.
///
/// All methods are `static`; no instance state. Pass per-frame values in `draw(…)`.
public enum SpectralCartographText {

    // MARK: - Entry point

    /// Draw all typographic labels for one frame of the Spectral Cartograph dashboard.
    ///
    /// - Parameters:
    ///   - ctx:           CGContext backed by DynamicTextOverlay (top-left origin after CTM flip).
    ///   - size:          Canvas dimensions (2 048 × 1 024 by default).
    ///   - bpm:           Current BPM from the SpectralHistoryBuffer (0 = no grid).
    ///   - lockState:     Drift-tracker lock state: 0 = unlocked, 1 = locking, 2 = locked.
    ///   - sessionMode:   0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked.
    ///   - beatPhase01:   Current beat phase [0, 1] from FeatureVector.
    ///   - barPhase01:    Current bar phase [0, 1] from FeatureVector (0 = no grid).
    ///   - beatsPerBar:   Time-signature numerator from installed BeatGrid (default 4).
    ///   - driftMs:       Drift-tracker correction in ms (0 = no grid / reactive mode).
    ///   - phaseOffsetMs: Developer visual phase offset in ms; shown in amber when non-zero.
    public static func draw(
        in ctx: CGContext,
        size: CGSize,
        bpm: Float,
        lockState: Int,
        sessionMode: Int = 0,
        beatPhase01: Float = 0,
        barPhase01: Float = 0,
        beatsPerBar: Int = 4,
        driftMs: Float = 0,
        phaseOffsetMs: Float = 0
    ) {
        // DynamicTextOverlay.refresh() already sets textMatrix = CGAffineTransform(scaleX:1,y:-1)
        // to fix Core Text mirroring in the flipped CTM. Do NOT override with .identity here.

        let cw = size.width   // 2048
        let ch = size.height  // 1024

        // ── Panel header labels ───────────────────────────────────────────────────
        let headerFont = ctFont("SFMono-Semibold", size: 15)
        let headerColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

        let hdrPos0 = metalToCG(0.012, 0.036, cw, ch)
        let hdrPos1 = metalToCG(0.512, 0.036, cw, ch)
        let hdrPos2 = metalToCG(0.012, 0.536, cw, ch)
        let hdrPos3 = metalToCG(0.512, 0.536, cw, ch)
        drawLabel("FFT SPECTRUM", at: hdrPos0, font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("BAND DEVIATION", at: hdrPos1, font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("VALENCE / AROUSAL", at: hdrPos2, font: headerFont, color: headerColor, ctx: ctx)
        drawLabel("TIMESERIES  8 s", at: hdrPos3, font: headerFont, color: headerColor, ctx: ctx)

        // ── TR: band row labels and axis ticks ────────────────────────────────────
        let rowFont = ctFont("SFMono-Regular", size: 11)
        let rowDim = CGColor(red: 0.68, green: 0.68, blue: 0.68, alpha: 1)
        let tickFont = ctFont("SFMono-Regular", size: 9)
        let tickDim = CGColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1)

        let trLabelX: Double = 0.513
        drawLabel("BASS", at: metalToCG(trLabelX, 0.196, cw, ch), font: rowFont, color: rowDim, ctx: ctx)
        drawLabel("MID", at: metalToCG(trLabelX, 0.333, cw, ch), font: rowFont, color: rowDim, ctx: ctx)
        drawLabel("TREBLE", at: metalToCG(trLabelX, 0.470, cw, ch), font: rowFont, color: rowDim, ctx: ctx)

        drawLabel("–1", at: metalToCG(0.532, 0.060, cw, ch), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("0", at: metalToCG(0.740, 0.060, cw, ch), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("+1", at: metalToCG(0.960, 0.060, cw, ch), font: tickFont, color: tickDim, ctx: ctx)

        // ── BL: valence/arousal axis labels + quadrant hints ──────────────────────
        let axFont = ctFont("SFMono-Regular", size: 9)
        let axDim = CGColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1)
        let qdFont = ctFont("SFMono-Regular", size: 8)
        let qdDim = CGColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1)

        drawLabel("–1 NEGATIVE", at: metalToCG(0.015, 0.975, cw, ch), font: axFont, color: axDim, ctx: ctx)
        drawLabel("POSITIVE +1", at: metalToCG(0.370, 0.975, cw, ch), font: axFont, color: axDim, ctx: ctx)
        drawLabel("HIGH", at: metalToCG(0.015, 0.570, cw, ch), font: axFont, color: axDim, ctx: ctx)
        drawLabel("LOW", at: metalToCG(0.015, 0.965, cw, ch), font: axFont, color: axDim, ctx: ctx)

        drawLabel("joy", at: metalToCG(0.390, 0.620, cw, ch), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("stress", at: metalToCG(0.030, 0.620, cw, ch), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("sad", at: metalToCG(0.030, 0.940, cw, ch), font: qdFont, color: qdDim, ctx: ctx)
        drawLabel("calm", at: metalToCG(0.390, 0.940, cw, ch), font: qdFont, color: qdDim, ctx: ctx)

        // ── BR: timeseries row labels + time axis ─────────────────────────────────
        let beatPhaseClr = CGColor(red: 1.0, green: 0.784, blue: 0.341, alpha: 0.9)
        let bassDevClr = CGColor(red: 1.0, green: 0.361, blue: 0.361, alpha: 0.9)
        let barPhaseClr = CGColor(red: 0.482, green: 0.361, blue: 1.0, alpha: 0.9)

        drawLabel("BEAT φ", at: metalToCG(0.513, 0.605, cw, ch), font: rowFont, color: beatPhaseClr, ctx: ctx)
        drawLabel("BASS DEV", at: metalToCG(0.513, 0.742, cw, ch), font: rowFont, color: bassDevClr, ctx: ctx)
        drawLabel("BAR φ", at: metalToCG(0.513, 0.879, cw, ch), font: rowFont, color: barPhaseClr, ctx: ctx)

        drawLabel("← 8 s", at: metalToCG(0.515, 0.975, cw, ch), font: tickFont, color: tickDim, ctx: ctx)
        drawLabel("now →", at: metalToCG(0.930, 0.975, cw, ch), font: tickFont, color: tickDim, ctx: ctx)

        // ── Beat orb: BPM + session-mode label ───────────────────────────────────
        drawBPM(bpm, orbAboveY: 0.220, ctx: ctx, cw: cw, ch: ch)
        drawModeLabel(sessionMode: sessionMode, orbBelowY: 0.770, ctx: ctx, cw: cw, ch: ch)

        // ── DSP.3.3 diagnostic readouts ───────────────────────────────────────────
        // These appear below the mode label in the clear space between the orb and
        // the bottom panels. Large enough to read at a glance during live diagnosis.
        drawBeatInBar(
            beatPhase01: beatPhase01, barPhase01: barPhase01, beatsPerBar: beatsPerBar,
            lockState: lockState, y: 0.825, ctx: ctx, cw: cw, ch: ch
        )
        drawDriftReadout(
            driftMs: driftMs, phaseOffsetMs: phaseOffsetMs,
            lockState: lockState, y: 0.875, ctx: ctx, cw: cw, ch: ch
        )
    }

    // MARK: - BPM

    private static func drawBPM(
        _ bpm: Float,
        orbAboveY: Double,
        ctx: CGContext,
        cw: CGFloat,
        ch: CGFloat
    ) {
        let bpmI = Int(bpm + 0.5)
        guard bpmI > 0 && bpmI < 1000 else { return }

        let bpmFont = ctFont("SFMono-Bold", size: 32)
        let bpmColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let bpmStr = "\(bpmI) BPM"
        let line = ctLine(bpmStr, font: bpmFont, color: bpmColor)

        let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgPos = metalToCG(0.5 - (lineW / cw) * 0.5, orbAboveY, cw, ch)
        ctx.textPosition = cgPos
        CTLineDraw(line, ctx)
    }

    // MARK: - Mode label

    /// Draw the session-mode label below the beat orb.
    ///
    /// Mapping:
    ///   sessionMode 0 → "○ REACTIVE"            (grey — no grid)
    ///   sessionMode 1 → "◐ PLANNED · UNLOCKED"  (muted yellow — grid present, < 4 matched onsets)
    ///   sessionMode 2 → "◑ PLANNED · LOCKING"   (yellow-green — grid present, approaching lock)
    ///   sessionMode 3 → "● PLANNED · LOCKED"    (bright green — grid locked)
    private static func drawModeLabel(
        sessionMode: Int,
        orbBelowY: Double,
        ctx: CGContext,
        cw: CGFloat,
        ch: CGFloat
    ) {
        let lockFont = ctFont("SFMono-Regular", size: 13)
        let (lockStr, lockColor): (String, CGColor) = {
            switch sessionMode {
            case 3:
                return ("● PLANNED · LOCKED", CGColor(red: 0.30, green: 1.00, blue: 0.30, alpha: 1))
            case 2:
                return ("◑ PLANNED · LOCKING", CGColor(red: 0.70, green: 1.00, blue: 0.20, alpha: 1))
            case 1:
                return ("◐ PLANNED · UNLOCKED", CGColor(red: 1.00, green: 0.85, blue: 0.20, alpha: 0.8))
            default:
                return ("○ REACTIVE", CGColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1))
            }
        }()
        let line = ctLine(lockStr, font: lockFont, color: lockColor)
        let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgPos = metalToCG(0.5 - (lineW / cw) * 0.5, orbBelowY, cw, ch)
        ctx.textPosition = cgPos
        CTLineDraw(line, ctx)
    }

    // MARK: - DSP.3.3 Beat-in-bar counter

    /// Draw the beat-in-bar counter: e.g. "3 / 4" in large bold text.
    ///
    /// Only shown when a BeatGrid is installed (lockState ≥ 1) and beatsPerBar > 1.
    /// The beat index is derived from barPhase01: beatInBar = floor(barPhase01 * beatsPerBar) + 1.
    private static func drawBeatInBar(
        beatPhase01: Float,
        barPhase01: Float,
        beatsPerBar: Int,
        lockState: Int,
        y: Double,
        ctx: CGContext,
        cw: CGFloat,
        ch: CGFloat
    ) {
        guard lockState >= 1, beatsPerBar > 0 else { return }

        let bpb = max(1, beatsPerBar)
        let beatIndex = Int(barPhase01 * Float(bpb)) + 1
        let safeBeatIndex = max(1, min(beatIndex, bpb))

        let beatFont = ctFont("SFMono-Bold", size: 28)
        // Colour: amber at beat 1 (downbeat), white otherwise.
        let isDownbeat = safeBeatIndex == 1
        let beatColor = isDownbeat
            ? CGColor(red: 1.0, green: 0.784, blue: 0.341, alpha: 1.0)
            : CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        let str = "\(safeBeatIndex) / \(bpb)"
        let line = ctLine(str, font: beatFont, color: beatColor)
        let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgPos = metalToCG(0.5 - (lineW / cw) * 0.5, y, cw, ch)
        ctx.textPosition = cgPos
        CTLineDraw(line, ctx)
    }

    // MARK: - DSP.3.3 Drift + phase offset readout

    /// Draw the drift tracker correction and optional visual phase offset.
    ///
    /// Format: "Δ drift = +12 ms" in muted colour; shown only when grid is active.
    /// If phaseOffsetMs ≠ 0, adds a second line: "offset = +10 ms" in amber.
    private static func drawDriftReadout(
        driftMs: Float,
        phaseOffsetMs: Float,
        lockState: Int,
        y: Double,
        ctx: CGContext,
        cw: CGFloat,
        ch: CGFloat
    ) {
        let diagFont = ctFont("SFMono-Regular", size: 13)
        let diagDim = CGColor(red: 0.50, green: 0.70, blue: 0.50, alpha: 0.85)
        let offsetAmber = CGColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 0.9)

        // Drift line: shown whenever lockState ≥ 1 (grid installed).
        if lockState >= 1 {
            let sign = driftMs >= 0 ? "+" : ""
            let str = "Δ drift = \(sign)\(Int(driftMs.rounded())) ms"
            let line = ctLine(str, font: diagFont, color: diagDim)
            let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
            let cgPos = metalToCG(0.5 - (lineW / cw) * 0.5, y, cw, ch)
            ctx.textPosition = cgPos
            CTLineDraw(line, ctx)
        }

        // Phase offset line: shown only when the developer has applied a visual offset.
        let offsetAbs = abs(phaseOffsetMs)
        if offsetAbs > 0.5 {
            let sign = phaseOffsetMs >= 0 ? "+" : ""
            let str = "offset = \(sign)\(Int(phaseOffsetMs.rounded())) ms"
            let line = ctLine(str, font: diagFont, color: offsetAmber)
            let lineW = CTLineGetTypographicBounds(line, nil, nil, nil)
            let offsetY = y + 0.040  // one line below drift
            let cgPos = metalToCG(0.5 - (lineW / cw) * 0.5, offsetY, cw, ch)
            ctx.textPosition = cgPos
            CTLineDraw(line, ctx)
        }
    }

    // MARK: - Helpers

    /// Convert Metal UV coordinates to CGContext pixels.
    ///
    /// After DynamicTextOverlay's CTM flip, user-space y=0 = screen top and y=h = screen bottom,
    /// matching Metal UV convention directly.  No Y-flip needed here.
    private static func metalToCG(
        _ mx: Double, _ my: Double,
        _ cw: CGFloat, _ ch: CGFloat
    ) -> CGPoint {
        return CGPoint(x: CGFloat(mx) * cw, y: CGFloat(my) * ch)
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
        let nsStr = NSAttributedString(string: str, attributes: [
            .font: font as Any,
            .foregroundColor: color as Any
        ])
        return CTLineCreateWithAttributedString(nsStr)
    }

    /// Create a CTFont by PostScript name with system-font fallback.
    ///
    /// Tried names:
    ///   SFMono-Bold, SFMono-Semibold, SFMono-Regular  (SF Mono — macOS 10.12+)
    ///   Menlo-Bold, Menlo-Regular                       (safe fallback)
    private static func ctFont(_ name: String, size: CGFloat) -> CTFont {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let actualName = CTFontCopyPostScriptName(font) as String
        if actualName.lowercased().contains("lastresort") || actualName == ".AppleLastResortFont" {
            let fallbackName = name.contains("Bold") ? "Menlo-Bold" : "Menlo-Regular"
            return CTFontCreateWithName(fallbackName as CFString, size, nil)
        }
        return font
    }
}
