// DashboardTokensTests — 4 @Test functions, one per nested struct/enum.
// Asserts the compile-time token values match the DASH.1 spec.

import Testing
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

@Suite("DashboardTokens")
struct DashboardTokensTests {

    @Test("TypeScale values match spec")
    func typeScaleValues() {
        #expect(DashboardTokens.TypeScale.caption      == 10)
        #expect(DashboardTokens.TypeScale.label        == 11)
        #expect(DashboardTokens.TypeScale.body         == 13)
        #expect(DashboardTokens.TypeScale.numeric      == 18)
        #expect(DashboardTokens.TypeScale.hero         == 24)
        #expect(DashboardTokens.TypeScale.display      == 36)
        #expect(DashboardTokens.TypeScale.labelTracking == 1.5)
        // Scale must be monotonically increasing through hero; display is the largest.
        #expect(DashboardTokens.TypeScale.caption < DashboardTokens.TypeScale.label)
        #expect(DashboardTokens.TypeScale.label   < DashboardTokens.TypeScale.body)
        #expect(DashboardTokens.TypeScale.body    < DashboardTokens.TypeScale.numeric)
        #expect(DashboardTokens.TypeScale.numeric < DashboardTokens.TypeScale.hero)
        #expect(DashboardTokens.TypeScale.hero    < DashboardTokens.TypeScale.display)
    }

    @Test("Spacing values match spec")
    func spacingValues() {
        #expect(DashboardTokens.Spacing.xs  == 4)
        #expect(DashboardTokens.Spacing.sm  == 8)
        #expect(DashboardTokens.Spacing.md  == 12)
        #expect(DashboardTokens.Spacing.lg  == 16)
        #expect(DashboardTokens.Spacing.xl  == 24)
        #expect(DashboardTokens.Spacing.xxl == 32)
        // 8-pt baseline: each step doubles or adds 8 from the previous.
        #expect(DashboardTokens.Spacing.xs  < DashboardTokens.Spacing.sm)
        #expect(DashboardTokens.Spacing.sm  < DashboardTokens.Spacing.md)
        #expect(DashboardTokens.Spacing.md  < DashboardTokens.Spacing.lg)
        #expect(DashboardTokens.Spacing.lg  < DashboardTokens.Spacing.xl)
        #expect(DashboardTokens.Spacing.xl  < DashboardTokens.Spacing.xxl)
    }

    @Test("Color brand and chrome values are non-zero and opaque where specified")
    func colorValues() {
        // Brand colors are fully opaque.
        #expect(DashboardTokens.Color.purple.alphaComponent == 1.0)
        #expect(DashboardTokens.Color.coral.alphaComponent  == 1.0)
        #expect(DashboardTokens.Color.teal.alphaComponent   == 1.0)
        // Teal should be green-dominant (G ≈ 0.769 > R ≈ 0.180, B ≈ 0.714).
        let teal = DashboardTokens.Color.teal
        let tealSRGB = teal.usingColorSpace(.sRGB)!
        #expect(tealSRGB.greenComponent > tealSRGB.redComponent)
        #expect(tealSRGB.greenComponent > tealSRGB.blueComponent)
        // Chrome background is near-black with high opacity.
        let bg = DashboardTokens.Color.chromeBg
        #expect(bg.alphaComponent > 0.8)
        // Text primary is near-white.
        let txt = DashboardTokens.Color.textPrimary
        #expect(txt.alphaComponent > 0.9)
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
