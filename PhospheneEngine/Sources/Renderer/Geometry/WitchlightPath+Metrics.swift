// WitchlightPath+Metrics.swift — the QG.5 seam.
//
// Split out of `WitchlightPath.swift` at WL.2-i: adding `penSpeedSwing` pushed that file to
// 401 lines against the 400-line lint. The metrics are a natural seam — they are read by
// gates, never by the render path — so they move together rather than the rationale for
// them being trimmed to fit.

import Foundation
import Shared

// MARK: - Hue recovery

extension WitchlightPath {
    /// Hue from a bead's stored RGB. Beads carry colour, not hue (the GPU never sees a hue),
    /// so the `bead_hue` metric recovers it. Exact for this preset's palette: every bead is
    /// laid at S 0.80 / V 1.0, so the standard max/min reconstruction is lossless here.
    static func hueOf(red: Float, green: Float, blue: Float) -> Float {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let delta = maxC - minC
        guard delta > 1e-6 else { return 0 }
        let hue: Float
        if maxC == red {
            hue = (green - blue) / delta
        } else if maxC == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        let scaled = hue / 6
        return scaled - floor(scaled)
    }
}

// MARK: - AudioResponseMetrics (QG.5)

extension WitchlightPath {

    /// Turns of pen heading per trail window — the quantity that decides whether the
    /// stroke reads as a figure or as an arc.
    ///
    /// Normalised per trail window rather than reported as a raw total, because fixtures
    /// differ in length and a raw total would make the band depend on fixture duration
    /// instead of on the preset. Measured from the WL.2-a probe renders: legible figures
    /// landed at 1.9–2.8 turns; the shipped fixed gain produces 0.20–0.73 and draws an
    /// arc on every fixture.
    public func responseMetric(_ name: String) -> Double? {
        switch name {
        case "headingTurnsPerTrail":
            guard elapsedSeconds > 0.01 else { return nil }
            let perSecond = Double(headingTravel) / elapsedSeconds
            return perSecond * Double(tuning.trailSeconds) / (2 * .pi)
        case "penSpeedSwing":
            // Ratio of fastest to slowest pen speed. Reported as a RATIO, not a delta, so
            // the band is independent of `baseSpeed` — a later change to how fast the pen
            // travels must not silently move this gate.
            //
            // Exists because Matt's second M7 ("the same choices about movement") landed on
            // an UNGATED route: of Witchlight's eight audio routes only `headingTurnsPerTrail`
            // carried a QG.5 band, so a speed layer realising a 13 % swing shipped green.
            // That is precisely the failure QG.5 was built for, one route over.
            guard speedMax > 0, speedMin < .greatestFiniteMagnitude, speedMin > 1e-6 else { return nil }
            return Double(speedMax / speedMin)
        case "ribbonBreathSwing":
            // Range of the per-frame energy breath, as a SPAN of the 0…1 signal rather than a
            // ratio: it is centred on 0.5, so a ratio would explode near the centre and say
            // nothing. 0 means the ribbon never breathed.
            //
            // This route exists because Matt's fourth M7 was "not synced to the music", and
            // the measurement behind it was that Witchlight had NO per-frame energy coupling
            // at all — every one of its eight routes ran on a 1–30 s or slower envelope while
            // every loudness band sat alive and unrouted. The band exists so that can never
            // silently become true again.
            guard breathMax > 0, breathMin < .greatestFiniteMagnitude else { return nil }
            return Double(breathMax - breathMin)
        default:
            return routeMetricWL12(name)
        }
    }

    /// Circular spread of the hues currently in the trail, 0…1.
    ///
    /// The `bead_hue` route's whole claim is that the ribbon's colour banding IS the track's
    /// harmonic history. If the hue freezes the trail becomes one colour and the claim is
    /// false — while every other gate stays green, because a monochrome ribbon is still a
    /// lit, distinct, correctly-framed ribbon.
    ///
    /// Circular, not min/max: hue wraps, so a trail spanning 0.95 → 0.05 is a NARROW band
    /// that a linear range would score as maximal. Measured as the complement of the largest
    /// empty arc — the standard circular-range construction, and exactly the quantity a
    /// viewer reads as "how many colours are in this ribbon".
    private func beadHueSpread() -> Double? {
        guard beads.count >= 8 else { return nil }
        var hues = beads.map { Self.hueOf(red: $0.colR, green: $0.colG, blue: $0.colB) }.sorted()
        guard let first = hues.first else { return nil }
        hues.append(first + 1)
        var widestGap: Float = 0
        for i in 0..<(hues.count - 1) { widestGap = max(widestGap, hues[i + 1] - hues[i]) }
        return Double(max(0, 1 - widestGap))
    }

    /// The four WL.12 route metrics, split out purely so `responseMetric` stays inside the
    /// cyclomatic-complexity budget — one switch of eight cases exceeds it.
    private func routeMetricWL12(_ name: String) -> Double? {
        switch name {
        // MARK: - WL.12 — the four routes that shipped certified with no band
        //
        // Five of eight routes carried no QG.5 band at certification, meaning a future change
        // could kill any of them with every gate green — which is exactly how WL.2 shipped a
        // speed route realising a 13 % swing. Four are measurable from this seam. The fifth,
        // `nebula_hue`, is NOT — see the note at the end of this file.
        case "beadHueSpread":
            return beadHueSpread()
        case "promotedShareOfTrail":
            // `bead_promotion` — the visible chain of bar markers. Reported as a SHARE of the
            // live trail rather than a count, so it does not move with trail length or tempo.
            // 0 means the downbeat left no mark; the route is dead.
            guard !beads.isEmpty else { return nil }
            let promoted = beads.reduce(into: 0) { if $1.promoted > 0.5 { $0 += 1 } }
            return Double(promoted) / Double(beads.count)
        case "pulsesPerMinute":
            // `head_flare` — both tiers, because the route's claim is "something happens at
            // the moment of the beat" and either tier satisfies it. Per MINUTE rather than
            // per bar so a tempo change cannot mask a dead accent.
            guard elapsedSeconds > 5 else { return nil }
            return Double(flareCount + offBeatCount) * 60.0 / elapsedSeconds
        case "trailContractionDepth":
            // `trail_contraction` — the structural route. Its visible consequence is the trail
            // shortening at a section boundary; 0 means no boundary ever reached the path.
            // Nil rather than 0 when the fixture contains no section change at all, so the
            // band measures the ROUTE and not the fixture's structure.
            guard sectionEventCount > 0 else { return nil }
            return Double(contractionPeak)
        default:
            return nil
        }
    }
}

// MARK: - `nebula_hue` is deliberately NOT banded (WL.12)
//
// The other four unbanded routes joined the gate at WL.12. `nebula_hue` cannot, and the
// reason is structural rather than a matter of effort: the nebula's hue is computed in
// `witchlight_sky_fragment` from `features.valence`, on the GPU. Nothing about it exists on
// the CPU, so this seam — which is a `WitchlightPath` method — has no access to the quantity
// that would need measuring. Measuring `valence` itself is not a substitute: that is the
// PRIMITIVE, and `RouteCoverageTests` already asserts it varies. A band that re-asserted the
// input while the shader ignored it would be worse than no band, because it would read green.
//
// This is the same gap `RENDER_CAPABILITY_REGISTRY.md` records for mesh presets — QG.5
// reaches Swift-side visual state, not shader-side. Closing it needs either a CPU mirror of
// the fragment's hue maths or GPU readback, which is its own infrastructure increment and
// would serve every preset with a shader-computed visual quantity, not just this one.
