// PunchEnergyDriverTests — FBS Stage 2: punch height from passage loudness.
//
// The kickoff contract: loud → tall, soft → small, a floor so every beat
// registers while music plays; the beat keeps the timing, energy sets ONLY
// the size. The driver (`RenderPipeline.punchEnergyStep`) is an asymmetric
// EMA over the total stem energy — the signal measured (sessions
// `2026-06-11T01-56-22Z` / `2026-06-10T20-26-37Z`) to survive the AGC:
// So What's bass+piano intro reads ~0.33 vs 0.8–1.5 with the band in,
// while the AGC'd FeatureVector band sum is flat ~0.25 throughout.
// These tests pin (a) the rise/fall character, (b) the real-session
// separation the whole feature exists for.

import XCTest
@testable import Renderer

final class PunchEnergyDriverTests: XCTestCase {

    private let dt: Float = 1.0 / 60.0

    /// The shader's height mapping (fo_spike_strength Stage 2 block),
    /// mirrored here so the fixture test can assert in HEIGHT units.
    private func heightScale(_ smoothed: Float) -> Float {
        let e = min(max((smoothed - 0.25) / 0.75, 0), 1)
        let s = e * e * (3 - 2 * e)
        return 0.30 + 0.70 * s
    }

    /// Loudness transitions complete over ~3τ ≈ 7.5 s, both directions —
    /// symmetric BY MEASUREMENT (a fast-rise variant peak-followed So What's
    /// bursty intro; see `punchEnergyTau`). No per-frame cliffs either way.
    func test_symmetricResponse_transitionsOverSeconds_noCliffs() {
        var s: Float = 0
        var t: Float = 0
        var maxStep: Float = 0
        while t < 7.5 {
            let n = RenderPipeline.punchEnergyStep(smoothed: s, totalStemEnergy: 1.2, dt: dt)
            maxStep = max(maxStep, abs(n - s)); s = n; t += dt
        }
        XCTAssertGreaterThan(s / 1.2, 0.94, "a loud passage reaches ~full envelope by 3τ")
        var t2: Float = 0
        while t2 < 1.0 { s = RenderPipeline.punchEnergyStep(smoothed: s, totalStemEnergy: 0.3, dt: dt); t2 += dt }
        XCTAssertGreaterThan(s, 0.7, "a breakdown eases down, not cliffs (1 s after the drop)")
        while t2 < 7.5 { s = RenderPipeline.punchEnergyStep(smoothed: s, totalStemEnergy: 0.3, dt: dt); t2 += dt }
        XCTAssertEqual(s, 0.3, accuracy: 0.06, "settled near the quiet level by ~3τ fall")
        XCTAssertLessThan(maxStep, 0.01, "the envelope must glide, never step")
    }

    /// The reason this feature exists, on the real recording (FA #27): So
    /// What's quiet bass+piano intro must produce gentle punches (height
    /// near the floor) while the full-band sections punch at ~full height.
    func test_soWhatFixture_introGentle_bandFull() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "stemsum_so_what_2026-06-11T01-56-22Z",
                              withExtension: "csv", subdirectory: "fbs"),
            "real-session stem-sum fixture missing (FA #27)")
        let text = try String(contentsOf: url, encoding: .utf8)
        var smoothed: Float = 0
        var introHeights: [Float] = []   // te 3–9: bass+piano only
        var bandHeights: [Float] = []    // te 15–25: full band
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",").compactMap { Float($0) }
            guard c.count >= 3 else { continue }
            let (te, dtF, sum) = (c[0], max(0.001, min(0.1, c[1])), c[2])
            smoothed = RenderPipeline.punchEnergyStep(smoothed: smoothed,
                                                      totalStemEnergy: sum, dt: dtF)
            if te >= 3, te < 9 { introHeights.append(heightScale(smoothed)) }
            if te >= 15, te < 25 { bandHeights.append(heightScale(smoothed)) }
        }
        XCTAssertGreaterThan(introHeights.count, 100)
        XCTAssertGreaterThan(bandHeights.count, 100)
        let intro = introHeights.reduce(0, +) / Float(introHeights.count)
        let band = bandHeights.reduce(0, +) / Float(bandHeights.count)
        XCTAssertLessThan(intro, 0.5,
                          "the quiet intro must punch gently (mean height \(intro))")
        XCTAssertGreaterThan(band, 0.85,
                             "the full-band section must punch at ~full height (mean \(band))")
        XCTAssertGreaterThan(band / intro, 1.8,
                             "the dynamics must be clearly readable (band/intro = \(band / intro))")
    }
}
