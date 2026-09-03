// ApertureColor — the aperture's colour math, shared. (DS.4 / DS.5)
//
// Extracted from ApertureScene so ArrivalPushScene (DS.5) can use the identical
// prism/vibrancy math rather than a second, driftable copy. No behaviour change to
// ApertureScene — same types, same formulas, just no longer nested and private to it.

import SwiftUI

// MARK: - RGB

/// A token colour resolved to RGB, so it can be mixed and made more or less vibrant.
struct ApertureRGB {
    /// sRGB channels, 0…1.
    var red01: Double, green01: Double, blue01: Double

    init(_ color: Color, _ env: EnvironmentValues) {
        let parts = color.resolve(in: env).cgColor.components ?? [0, 0, 0]
        red01 = Double(parts.isEmpty ? 0 : parts[0])
        green01 = Double(parts.count > 1 ? parts[1] : 0)
        blue01 = Double(parts.count > 2 ? parts[2] : 0)
    }

    init(red01: Double, green01: Double, blue01: Double) {
        self.red01 = red01; self.green01 = green01; self.blue01 = blue01
    }

    func mixed(with other: ApertureRGB, _ amount: Double) -> ApertureRGB {
        ApertureRGB(
            red01: red01 + (other.red01 - red01) * amount,
            green01: green01 + (other.green01 - green01) * amount,
            blue01: blue01 + (other.blue01 - blue01) * amount
        )
    }

    /// Rotate each channel around the colour's own luminance: a sliver of light is
    /// barely coloured, a wide opening is saturated past full. The hue never moves.
    func vibrant(_ vibrancy: Double) -> ApertureRGB {
        let luma = 0.2126 * red01 + 0.7152 * green01 + 0.0722 * blue01
        return ApertureRGB(
            red01: luma + (red01 - luma) * vibrancy,
            green01: luma + (green01 - luma) * vibrancy,
            blue01: luma + (blue01 - luma) * vibrancy
        )
    }

    func color(alpha: Double, lift: Double = 0) -> Color {
        Color(
            .sRGB,
            red: min(1, red01 + lift),
            green: min(1, green01 + lift),
            blue: min(1, blue01 + lift),
            opacity: alpha
        )
    }
}

// MARK: - Palette

/// The tokens the aperture (and its arrival transition) may use, resolved once per frame.
struct AperturePalette {
    /// violet → cyan → gold → ember → violet, closed into a loop.
    let spectrum: [ApertureRGB]
    let ivory: ApertureRGB
    let canvas: ApertureRGB
    let rock: ApertureRGB

    init(_ env: EnvironmentValues) {
        let loop: [Color] = [
            UzumeAppColor.violet, UzumeAppColor.cyan, UzumeAppColor.gold, UzumeAppColor.ember, UzumeAppColor.violet,
        ]
        spectrum = loop.map { ApertureRGB($0, env) }
        ivory = ApertureRGB(UzumeAppColor.ivory, env)
        canvas = ApertureRGB(UzumeAppColor.canvas, env)
        rock = ApertureRGB(UzumeAppColor.surface, env)
    }

    /// The identity's spectrum around the whole circle. Continuous, never banded.
    func prism(_ unit: Double, vibrancy: Double) -> ApertureRGB {
        let positions = [0.0, 0.30, 0.55, 0.80, 1.0]
        var wrapped = unit.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        var index = 0
        while index < positions.count - 2 && wrapped > positions[index + 1] { index += 1 }
        let amount = (wrapped - positions[index]) / (positions[index + 1] - positions[index])
        return spectrum[index].mixed(with: spectrum[index + 1], amount).vibrant(vibrancy)
    }
}
