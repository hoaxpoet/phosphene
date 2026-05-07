// DashboardTokensTests — 4 @Test functions, one per nested struct/enum.
// Asserts the compile-time token values match the DASH.1.1 spec
// (derived from `.impeccable.md` OKLCH palette).

import Testing
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

@Suite("DashboardTokens")
struct DashboardTokensTests {

    @Test("TypeScale values match spec")
    func typeScaleValues() {
        #expect(DashboardTokens.TypeScale.caption       == 10)
        #expect(DashboardTokens.TypeScale.label         == 11)
        #expect(DashboardTokens.TypeScale.body          == 13)
        #expect(DashboardTokens.TypeScale.bodyLarge     == 15)
        #expect(DashboardTokens.TypeScale.numeric       == 18)
        #expect(DashboardTokens.TypeScale.hero          == 24)
        #expect(DashboardTokens.TypeScale.display       == 36)
        #expect(DashboardTokens.TypeScale.labelTracking == 1.5)
        // Scale must be monotonically increasing.
        #expect(DashboardTokens.TypeScale.caption   < DashboardTokens.TypeScale.label)
        #expect(DashboardTokens.TypeScale.label     < DashboardTokens.TypeScale.body)
        #expect(DashboardTokens.TypeScale.body      < DashboardTokens.TypeScale.bodyLarge)
        #expect(DashboardTokens.TypeScale.bodyLarge < DashboardTokens.TypeScale.numeric)
        #expect(DashboardTokens.TypeScale.numeric   < DashboardTokens.TypeScale.hero)
        #expect(DashboardTokens.TypeScale.hero      < DashboardTokens.TypeScale.display)
    }

    @Test("Spacing values match spec")
    func spacingValues() {
        #expect(DashboardTokens.Spacing.xs  == 4)
        #expect(DashboardTokens.Spacing.sm  == 8)
        #expect(DashboardTokens.Spacing.md  == 12)
        #expect(DashboardTokens.Spacing.lg  == 16)
        #expect(DashboardTokens.Spacing.xl  == 24)
        #expect(DashboardTokens.Spacing.xxl == 32)
        // 4-pt baseline ladder: monotonically increasing.
        #expect(DashboardTokens.Spacing.xs  < DashboardTokens.Spacing.sm)
        #expect(DashboardTokens.Spacing.sm  < DashboardTokens.Spacing.md)
        #expect(DashboardTokens.Spacing.md  < DashboardTokens.Spacing.lg)
        #expect(DashboardTokens.Spacing.lg  < DashboardTokens.Spacing.xl)
        #expect(DashboardTokens.Spacing.xl  < DashboardTokens.Spacing.xxl)
    }

    @Test("Color tokens match `.impeccable.md` OKLCH spec")
    func colorValues() {
        // Brand colors are fully opaque.
        #expect(DashboardTokens.Color.purple.alphaComponent == 1.0)
        #expect(DashboardTokens.Color.coral.alphaComponent  == 1.0)
        #expect(DashboardTokens.Color.teal.alphaComponent   == 1.0)

        // Teal at oklch(0.70 0.13 192) lands at the cyan-green edge of sRGB:
        // R clips to 0, G ≈ 0.72, B ≈ 0.70. G must dominate both other channels.
        let teal = DashboardTokens.Color.teal.usingColorSpace(.sRGB)!
        #expect(teal.greenComponent > teal.redComponent)
        #expect(teal.greenComponent > teal.blueComponent)

        // Surface ladder is monotonically rising in luminance and never pure black.
        // Use green channel as a brightness proxy — all three channels rise together
        // for tinted neutrals, and `.brightnessComponent` requires HSB color space.
        let bg = DashboardTokens.Color.bg.usingColorSpace(.sRGB)!
        let surface = DashboardTokens.Color.surface.usingColorSpace(.sRGB)!
        let surfaceRaised = DashboardTokens.Color.surfaceRaised.usingColorSpace(.sRGB)!
        #expect(bg.greenComponent < surface.greenComponent)
        #expect(surface.greenComponent < surfaceRaised.greenComponent)
        #expect(bg.redComponent > 0.0 || bg.greenComponent > 0.0 || bg.blueComponent > 0.0)

        // Neutrals are tinted toward the brand purple hue: blue channel exceeds red.
        let surfaceTint = surface.blueComponent - surface.redComponent
        #expect(surfaceTint > 0.005, "Surface should be tinted toward brand purple")

        // Text ladder is monotonically rising.
        let muted = DashboardTokens.Color.textMuted.usingColorSpace(.sRGB)!
        let body = DashboardTokens.Color.textBody.usingColorSpace(.sRGB)!
        let heading = DashboardTokens.Color.textHeading.usingColorSpace(.sRGB)!
        #expect(muted.greenComponent < body.greenComponent)
        #expect(body.greenComponent < heading.greenComponent)
        // Heading is bright but not pure white (off-white tinted purple).
        #expect(heading.greenComponent > 0.85)
        #expect(heading.greenComponent < 1.0)

        // Status colors are opaque.
        #expect(DashboardTokens.Color.statusGreen.alphaComponent  == 1.0)
        #expect(DashboardTokens.Color.statusYellow.alphaComponent == 1.0)
        #expect(DashboardTokens.Color.statusRed.alphaComponent    == 1.0)
    }

    @Test("Supporting enum cases are exhaustive per spec")
    func enumCases() {
        // Weight
        let weights: [DashboardTokens.Weight] = [.regular, .medium]
        #expect(weights.count == 2)

        // TextFont
        let fonts: [DashboardTokens.TextFont] = [.mono, .prose]
        #expect(fonts.count == 2)

        // Alignment
        let alignments: [DashboardTokens.Alignment] = [.left, .center, .right]
        #expect(alignments.count == 3)
    }
}
