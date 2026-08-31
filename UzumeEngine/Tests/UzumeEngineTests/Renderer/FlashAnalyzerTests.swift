// FlashAnalyzerTests — synthetic self-check for the Harding / WCAG flash analyzer (CLEAN.7.6).
//
// Pins the detector semantics with hand-built luminance sequences at known
// flash rates: dangerous strobes trip, safe motion passes, and the two
// qualifying conditions (≥ 10 % swing, darker state < 0.80) gate correctly.
//
// This is the analyzer's correctness proof. The prompt's intended A/B against
// the FBS "373 events" video material is not runnable — that pre/post video
// was never committed (only 3-band feature CSVs survive). Synthetic sequences
// at known rates prove the detector more precisely than a single real-world
// A/B would, and need no fixtures (worktree-safe).

import Testing
@testable import Renderer

// MARK: - FlashAnalyzerTests

@Suite("Flash Analyzer (Harding / WCAG 2.3.1)")
struct FlashAnalyzerTests {

    /// A square wave alternating `low`/`high` at `hz` for `seconds` at `fps`.
    private func square(low: Double, high: Double, hz: Double, seconds: Double, fps: Double) -> [Double] {
        let count = Int(seconds * fps)
        let halfPeriod = fps / (2 * hz)   // frames per half-cycle
        return (0..<count).map { i in
            (Int(Double(i) / halfPeriod) % 2) == 0 ? low : high
        }
    }

    @Test("Steady luminance produces zero flashes")
    func steadyIsSafe() {
        let r = FlashAnalyzer.analyze(relativeLuminance: Array(repeating: 0.5, count: 120), fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.peakFlashesPerSecond == 0)
        #expect(r.isSafe)
    }

    @Test("Monotonic ramp produces zero flashes")
    func rampIsSafe() {
        let ramp = (0..<120).map { Double($0) / 119.0 }
        let r = FlashAnalyzer.analyze(relativeLuminance: ramp, fps: 60)
        #expect(r.peakFlashesPerSecond == 0)
        #expect(r.isSafe)
    }

    @Test("6 Hz full-swing strobe is unsafe")
    func fastStrobeIsUnsafe() {
        let s = square(low: 0.1, high: 0.9, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(!r.isSafe)
        #expect(r.peakFlashesPerSecond > 3.0)
    }

    @Test("2 Hz full-swing flash is safe")
    func slowFlashIsSafe() {
        let s = square(low: 0.1, high: 0.9, hz: 2, seconds: 3, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.isSafe)
        #expect(r.peakFlashesPerSecond <= 3.0)
        #expect(r.peakFlashesPerSecond >= 1.5)   // ~2/s, demonstrably not zero
    }

    // Bracket the 3/s limit without sitting on the float knife-edge of exactly 3.

    @Test("Just below the limit (2.5 Hz) is safe")
    func justBelowLimitIsSafe() {
        let s = square(low: 0.1, high: 0.9, hz: 2.5, seconds: 4, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.isSafe)
        #expect(r.peakFlashesPerSecond >= 2.0 && r.peakFlashesPerSecond <= 3.0)
    }

    @Test("Just above the limit (3.5 Hz) is unsafe")
    func justAboveLimitIsUnsafe() {
        let s = square(low: 0.1, high: 0.9, hz: 3.5, seconds: 4, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(!r.isSafe)
        #expect(r.peakFlashesPerSecond > 3.0)
    }

    @Test("Bright-only flashes (darker state ≥ 0.80) do not count")
    func brightOnlyIsSafe() {
        // 6 Hz, but both states are bright: darker = 0.82 ≥ 0.80 ceiling.
        let s = square(low: 0.82, high: 0.99, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.isSafe)
    }

    @Test("Sub-threshold swing (< 10 %) does not count")
    func subThresholdIsSafe() {
        // 6 Hz, but swing 0.07 < 0.10 → no qualifying transition.
        let s = square(low: 0.45, high: 0.52, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.isSafe)
    }
}
