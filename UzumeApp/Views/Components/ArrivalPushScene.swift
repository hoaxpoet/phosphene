// ArrivalPushScene — the camera moves through the aperture. (DS.5)
//
// Matt, live direction: "I want a literal camera move into the aperture. The screen should
// be filled with light as the camera enters the aperture, a brief pause, and then the show
// begins." Prototyped in the browser first (docs/reviews/DS.5/DESIGN.md) — a uniform zoom on
// the resting aperture reads as the light approaching the viewer, not the viewer moving in,
// because a flat scale has no parallax. What sells forward travel is streaks racing outward
// from the opening's own centre, past the frame edges, while the aperture itself only grows
// modestly as a supporting cue — the same technique any "flying toward a light" shot uses.
//
// The background is the real, unmodified ApertureScene — not a redrawn approximation of it —
// composited under the streak burst so the churn (colour drift, mote drift, mouth wobble)
// keeps going the whole way through, the same aperture finishing its arc rather than a static
// image being flown past.

import Session
import SwiftUI

// MARK: - ArrivalPushScene

/// One frame of the arrival: the aperture, plus the push that carries the listener through it.
struct ArrivalPushScene {
    var character: PreparationCharacter
    /// Scene time in seconds — drives the aperture background's own ongoing churn.
    var time: Double
    /// 0…1 through the push itself. Values beyond 1 are the caller's to hold as a pause;
    /// this type only draws what 0…1 (clamped) describes.
    var progress: Double

    private static let tau = Double.pi * 2

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let eased = pow(min(1, max(0, progress)), 3) // matches the prototype's accelerating curve
        let frame = ApertureScene.Frame(size: size, openness: 1, character: character, time: time)
        let palette = ApertureScene.Palette(ctx.environment)

        drawBackground(&ctx, size: size, eased: eased)
        guard eased > 0 else { return }
        let field = StreakField(centre: frame.centre, driftHue: frame.drift, eased: eased)
        drawStreaks(&ctx, size: size, field: field, palette: palette)
        drawWhiteout(&ctx, size: size, eased: eased, palette: palette)
    }

    /// The live, unmodified aperture, scaled modestly toward its own centre. A supporting
    /// cue, not the thing that sells the motion — see the streaks below.
    private func drawBackground(_ ctx: inout GraphicsContext, size: CGSize, eased: Double) {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.52)
        let scale = 1 + 3.2 * eased
        ctx.drawLayer { layer in
            layer.translateBy(x: centre.x, y: centre.y)
            layer.scaleBy(x: scale, y: scale)
            layer.translateBy(x: -centre.x, y: -centre.y)
            let aperture = ApertureScene(openness: 1, character: character, time: time)
            aperture.draw(in: &layer, size: size)
        }
    }

    /// A streak burst's shared inputs, bundled so `drawStreaks` stays within the parameter
    /// count gate — the same pattern `ApertureScene.FanLayer` already uses.
    private struct StreakField {
        let centre: CGPoint
        let driftHue: Double
        let eased: Double
    }

    /// Forward travel, not the light approaching: streaks from the opening's centre,
    /// accelerating outward past the frame edges as the push builds. The parallax between
    /// a fixed vanishing point and streaks racing past it is what reads as the viewer moving.
    private func drawStreaks(
        _ ctx: inout GraphicsContext,
        size: CGSize,
        field: StreakField,
        palette: ApertureScene.Palette
    ) {
        let centre = field.centre
        let diag = (size.width * size.width + size.height * size.height).squareRoot()
        let speed = field.eased * field.eased
        let count = 100
        ctx.blendMode = .plusLighter
        for i in 0..<count {
            let jitter = Double((i % 3) - 1) * 0.01
            let angle = Double(i) / Double(count) * Self.tau + jitter
            let dx = cos(angle), dy = sin(angle)
            let inner = diag * (0.01 + speed * 0.10) + Double(i % 7)
            let outer = min(diag * 1.35, inner + diag * (0.04 + speed * 1.05))
            let colour = palette.prism(Double(i) / Double(count) + field.driftHue, vibrancy: 0.95)
            let start = CGPoint(x: centre.x + dx * inner, y: centre.y + dy * inner)
            let end = CGPoint(x: centre.x + dx * outer, y: centre.y + dy * outer)

            var streak = Path()
            streak.move(to: start)
            streak.addLine(to: end)
            ctx.stroke(
                streak,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: colour.color(alpha: 0), location: 0),
                        .init(color: colour.color(alpha: 0.55 * speed), location: 0.45),
                        .init(color: colour.color(alpha: 0), location: 1),
                    ]),
                    startPoint: start,
                    endPoint: end
                ),
                lineWidth: 1.3 + speed * 3.2
            )
        }
    }

    /// The screen fills with light: a clean, uniform convergence over the last stretch of
    /// the push, arriving after the travel rather than standing in for it.
    private func drawWhiteout(
        _ ctx: inout GraphicsContext, size: CGSize, eased: Double, palette: ApertureScene.Palette
    ) {
        let whiteout = eased < 0.55 ? 0 : pow((eased - 0.55) / 0.45, 1.4)
        guard whiteout > 0 else { return }
        ctx.blendMode = .normal
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.ivory.color(alpha: whiteout)))
    }
}
