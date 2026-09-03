// ApertureScene — the cave, drawn. (DS.4 / D-238)
//
// A pure function of (openness, character, time, surge) → one frame, so a test can step
// it and measure luminance without a run loop. The SwiftUI shell is PreparationAperture.
//
// Colour: the ivory mouth and the identity's full performed-light spectrum, always. The
// four spectrum tokens are interpolated continuously around the whole circle — never
// banded — and their chroma rises with the aperture so a barely-cracked cave glimmers and
// a wide one saturates. No colour outside the vendored tokens.
//
// The spill is two conic-gradient discs (a smooth wash and a ribbed layer) under a
// radial-falloff mask: seamless by construction, and a handful of fills per frame rather
// than one per shaft — the GPU is separating stems behind this screen.

import SwiftUI

// MARK: - ApertureScene

/// One frame of the cave.
struct ApertureScene {
    var openness: Double
    var character: PreparationCharacter
    /// Scene time in seconds; the character's rate scales it.
    var time: Double
    /// 0…1 swell from the most recent track heard.
    var surge: Double = 0

    // MARK: Colour
    //
    // RGB/Palette/prism live in ApertureColor.swift, shared with ArrivalPushScene (DS.5)
    // so the arrival transition uses the identical colour math, not a second copy.
    typealias RGB = ApertureRGB
    typealias Palette = AperturePalette

    // MARK: Frame geometry

    /// Everything the stages share, derived once from the inputs.
    struct Frame {
        let size: CGSize
        let centre: CGPoint
        let open: Double
        let clock: Double
        let warm: Double
        let vibrancy: Double
        let sweep: Double
        let drift: Double
        let mouthW: Double
        let mouthH: Double
        let reach: Double
        /// Nothing spills while shut.
        let spill: Double

        var mouthR: Double { max(mouthW, mouthH) }
        var rect: Path { Path(CGRect(origin: .zero, size: size)) }

        init(size: CGSize, openness: Double, character: PreparationCharacter, time: Double) {
            self.size = size
            open = min(1, max(0, openness))
            clock = time * character.rate
            warm = 0.32 + character.depth * 0.54
            vibrancy = 0.26 + open * 1.02
            // Exactly one loop of the prism around the circle, so the conic gradient
            // meets itself with no seam. Mood spread changes how fast it churns
            // (`drift`), never how much colour there is.
            sweep = 1
            drift = clock * (0.012 + character.moodSpread * 0.055)
            centre = CGPoint(x: size.width / 2, y: size.height * 0.52)
            let radius = max(0.01, open * min(size.width, size.height) * 0.30)
            mouthW = radius * (1 + character.heavy * 0.20)
            mouthH = radius * 0.82
            reach = max(size.width, size.height)
            spill = min(1, open * 14)
        }
    }

    private static let tau = Double.pi * 2

    // MARK: Draw

    /// Draw one frame.
    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let palette = Palette(ctx.environment)
        let frame = Frame(size: size, openness: openness, character: character, time: time)

        drawGround(&ctx, frame, palette)
        guard frame.spill > 0 else { return }
        ctx.blendMode = .plusLighter
        drawSpill(&ctx, frame, palette)
        drawMotes(&ctx, frame, palette)
        drawMouth(&ctx, frame, palette)
        drawBloom(&ctx, frame, palette)
        drawSurge(&ctx, frame, palette)
        ctx.blendMode = .normal
        drawVignette(&ctx, frame, palette)
    }

    /// The canvas, with the rock faintly lit around the mouth.
    private func drawGround(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        ctx.fill(frame.rect, with: .color(palette.canvas.color(alpha: 1)))
        ctx.fill(
            frame.rect,
            with: .radialGradient(
                Gradient(colors: [palette.rock.color(alpha: 1), palette.canvas.color(alpha: 1)]),
                center: frame.centre,
                startRadius: frame.mouthW * 0.6,
                endRadius: frame.reach * 0.8
            )
        )
    }

    /// The spill: a fan whose rate, edge, definition and reach are the playlist's. It
    /// radiates in every direction — an opening, not a spotlight.
    private func drawSpill(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        let look = character
        let clock = frame.clock
        let ribs = Double(Int(46 + look.beat * 54))
        let base = (0.085 + 0.075 * look.crisp) * frame.warm * (0.38 + frame.open * 1.05) * frame.spill
        let reachFactor = (0.55 + frame.open * 0.80) * (0.75 + look.energy * 0.5)
        let breathe = 1 + 0.06 * sin(clock * 0.6)
        let washReach = frame.reach * 0.78 * reachFactor * breathe
        let ribReach = frame.reach * 0.62 * reachFactor * (1 + 0.10 * look.beat * sin(clock * 0.9 + 1))
        let ribDepth = look.crisp * (0.35 + look.beat * 0.55)
        let ribPhase = clock * 0.35 + look.jitter * 4 * sin(clock * 0.9)

        // The wash: continuous, the vocals' share widens it.
        drawFan(&ctx, frame, palette, FanLayer(reach: washReach, lift: 0.02 * look.crisp)) { _ in
            base * 3.2 * (0.9 + look.wash * 0.8)
        }
        // The ribs: definition from the drums' share, edge from the centroid. Two
        // phases at two reaches, so neighbouring shafts differ in length.
        drawFan(&ctx, frame, palette, FanLayer(reach: ribReach, lift: 0.07 * look.crisp)) { frac in
            base * 3.8 * ribDepth * (0.5 + 0.5 * cos(frac * ribs * Self.tau + ribPhase))
        }
        drawFan(&ctx, frame, palette, FanLayer(reach: ribReach * 0.72, lift: 0.04 * look.crisp)) { frac in
            base * 3.0 * ribDepth * (0.5 + 0.5 * cos(frac * ribs * Self.tau + ribPhase + .pi))
        }
    }

    /// Reach and lift of one fan layer.
    private struct FanLayer {
        let reach: Double
        let lift: Double
    }

    /// One conic-gradient disc of the full prism, under a radial-falloff mask.
    private func drawFan(
        _ ctx: inout GraphicsContext,
        _ frame: Frame,
        _ palette: Palette,
        _ fan: FanLayer,
        alpha: (Double) -> Double
    ) {
        let reach = fan.reach, lift = fan.lift
        let steps = 96
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(steps + 1)
        for step in 0...steps {
            let frac = Double(step % steps) / Double(steps)
            let colour = palette.prism(frame.drift + frac * frame.sweep, vibrancy: frame.vibrancy)
            let location = Double(step) / Double(steps)
            stops.append(.init(color: colour.color(alpha: alpha(frac), lift: lift), location: location))
        }
        let disc = Path(ellipseIn: CGRect(
            x: frame.centre.x - reach, y: frame.centre.y - reach, width: reach * 2, height: reach * 2
        ))
        let centre = frame.centre
        let angle = Angle.radians(frame.clock * 0.02)
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.clipToLayer { mask in
                mask.fill(disc, with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.85), location: 0.22),
                        .init(color: .white.opacity(0.40), location: 0.58),
                        .init(color: .white.opacity(0), location: 1),
                    ]),
                    center: centre,
                    startRadius: 0,
                    endRadius: reach
                ))
            }
            layer.fill(disc, with: .conicGradient(Gradient(stops: stops), center: centre, angle: angle))
        }
    }

    /// Motes drifting out of the opening.
    private func drawMotes(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        let clock = frame.clock
        for mote in 0..<36 {
            let seed = Double(mote) * 0.618033988749
            let seed01 = seed.truncatingRemainder(dividingBy: 1)
            let speed = 0.4 + (seed * 7).truncatingRemainder(dividingBy: 1) * 0.6
            let dist01 = (seed01 + clock * speed * 0.045).truncatingRemainder(dividingBy: 1)
            let angle = seed01 * Self.tau + clock * 0.02
            let dist = dist01 * frame.size.height * 0.62 * (0.5 + frame.open * 0.7)
            let x = frame.centre.x + cos(angle) * dist + sin(clock * 0.3 + seed * 9) * 12
            let y = frame.centre.y + sin(angle) * dist
            let side = 1.5 + (seed * 13).truncatingRemainder(dividingBy: 1) * 2
            let colour = palette.prism(frame.drift + (seed01 - 0.5) * frame.sweep, vibrancy: frame.vibrancy)
            ctx.fill(
                Path(CGRect(x: x, y: y, width: side, height: side)),
                with: .color(colour.color(alpha: (1 - dist01) * 0.30 * frame.warm * frame.spill, lift: 0.35))
            )
        }
    }

    /// The mouth — irregular rock, never a mechanism; its waver follows the beat.
    /// "Keep the ivory opening brighter than the surrounding spectrum." (BRAND.md)
    private func drawMouth(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        var mouth = Path()
        for step in 0...72 {
            let theta = Double(step) / 72 * Self.tau
            let wobble = 1 + (0.10 + character.jitter * 0.16) * sin(theta * 3 + 1.2) + 0.08 * sin(theta * 5 - 0.6)
                + 0.05 * sin(theta * 8 + 2.2 + frame.clock * 0.15)
            let point = CGPoint(
                x: frame.centre.x + cos(theta) * frame.mouthW * wobble,
                y: frame.centre.y + sin(theta) * frame.mouthH * wobble
            )
            if step == 0 { mouth.move(to: point) } else { mouth.addLine(to: point) }
        }
        mouth.closeSubpath()
        let ivory = palette.ivory
        let warm = frame.warm
        ctx.fill(mouth, with: .radialGradient(
            Gradient(stops: [
                .init(color: ivory.color(alpha: 0.86 + warm * 0.14, lift: 0.04), location: 0),
                .init(color: ivory.color(alpha: 0.70 * warm + 0.24), location: 0.34),
                .init(color: ivory.color(alpha: 0.26 * warm), location: 0.72),
                .init(color: ivory.color(alpha: 0), location: 1),
            ]),
            center: frame.centre,
            startRadius: 0,
            endRadius: frame.mouthR * 1.05
        ))
    }

    /// Prismatic bloom hugging the opening, so the rock edge reads as lit by the spectrum.
    private func drawBloom(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        for ring in 0..<3 {
            let hue = frame.drift + (Double(ring) / 3 - 0.5) * frame.sweep * 0.8
            let colour = palette.prism(hue, vibrancy: frame.vibrancy)
            let inner = colour.color(alpha: 0.13 * frame.warm * frame.spill, lift: 0.08)
            ctx.fill(frame.rect, with: .radialGradient(
                Gradient(colors: [inner, colour.color(alpha: 0)]),
                center: frame.centre,
                startRadius: frame.mouthR * 0.85,
                endRadius: frame.mouthR * (1.9 + Double(ring) * 0.5)
            ))
        }
    }

    /// A track landing: a swell, never a flash. Bounded so the per-frame luminance
    /// step stays well under the D-157 gate (measured by PreparationApertureTests).
    private func drawSurge(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        guard surge > 0 else { return }
        let hue = (Double(character.heard) * 0.37).truncatingRemainder(dividingBy: 1) - 0.5
        let colour = palette.prism(frame.drift + hue, vibrancy: frame.vibrancy)
        ctx.fill(frame.rect, with: .radialGradient(
            Gradient(colors: [colour.color(alpha: 0.16 * surge * frame.spill, lift: 0.3), colour.color(alpha: 0)]),
            center: frame.centre,
            startRadius: 0,
            endRadius: frame.mouthR * 2.6
        ))
    }

    /// Vignette back to the canvas, so the frame stays genuinely dark at its edges.
    private func drawVignette(_ ctx: inout GraphicsContext, _ frame: Frame, _ palette: Palette) {
        ctx.fill(frame.rect, with: .radialGradient(
            Gradient(colors: [palette.canvas.color(alpha: 0), palette.canvas.color(alpha: 0.82)]),
            center: frame.centre,
            startRadius: min(frame.size.width, frame.size.height) * 0.28,
            endRadius: frame.reach * 0.78
        ))
    }
}
