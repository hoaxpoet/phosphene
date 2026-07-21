// MultiPassFlashHarnessTests — CLEAN.7.6c. The faithful multi-pass / feedback half of
// the photosensitivity flash-safety gate (GAP-9). It closes the certified presets the
// single-pass FeatureVector harness (`PhotosensitivityCertificationTests`) renders static
// because their music response arrives through multi-pass rendering:
//
//   - Lumen Mosaic — ray_march + post_process + the 4-light CPU follower (slot 8)
//   - Dragon Bloom / Fata Morgana / Skein / Nacre / Floret / Glaze — mv_warp feedback
//   - Filigree / Mitosis / Cytokinesis — geometry-driven particle colonies
//
// Each is driven over the shared worst-case beat + stem train, its rendered full-frame
// WCAG relative luminance is measured by `FlashAnalyzer`, and the Harding/WCAG 2.3.1
// ≤ 3 flashes/s limit is asserted. Over-limit ⇒ a P1 safety finding to bring to Matt,
// NOT a number to tune away — the certified beat-luminance motion was hand-built safe
// (D-157 bounded per-beat footprint + steady global luminance; D-158).
//
// QG.3.1: the real render bodies moved to the shared `MultiPassRenderHarness` (one faithful
// headless render for two consumers — this gate + the QG.3 coupling report). This file now
// supplies the flash-specific drive (synthetic worst-case beat train) and reducer (WCAG
// relative luminance) and keeps the flash assertions. The render itself is unchanged.
//
// GPU test — manual-closeout suite. Drive + luminance primitives are shared with the
// single-pass gate via `FlashHarnessSupport`.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - MultiPassFlashHarnessTests

@Suite("Photosensitivity Multi-Pass Flash Harness (Harding / WCAG 2.3.1, CLEAN.7.6c)")
@MainActor
struct MultiPassFlashHarnessTests {

    private let harness = MultiPassRenderHarness(width: 320, height: 180)

    // MARK: - Gate (one test per preset → its own evidence line + assertion)

    @Test("Lumen Mosaic is flash-safe (rayMarch + follower, real headless render)")
    func lumenMosaicIsFlashSafe() throws {
        assertFlashSafe(name: "Lumen Mosaic", luma: try flashLuma("Lumen Mosaic"))
    }

    @Test("Dragon Bloom is flash-safe (mv_warp feedback, real headless render)")
    func dragonBloomIsFlashSafe() throws {
        assertFlashSafe(name: "Dragon Bloom", luma: try flashLuma("Dragon Bloom"))
    }

    @Test("Fata Morgana is flash-safe (mv_warp bespoke, real headless render)")
    func fataMorganaIsFlashSafe() throws {
        assertFlashSafe(name: "Fata Morgana", luma: try flashLuma("Fata Morgana"))
    }

    @Test("Skein is flash-safe (mv_warp canvas-hold + follower, real headless render)")
    func skeinIsFlashSafe() throws {
        assertFlashSafe(name: "Skein", luma: try flashLuma("Skein"))
    }

    @Test("Nacre is flash-safe (mv_warp feedback, downbeat camera push, real headless render)")
    func nacreIsFlashSafe() throws {
        assertFlashSafe(name: "Nacre", luma: try flashLuma("Nacre"))
    }

    @Test("Floret is flash-safe (mv_warp feedback, bass-kick ripple + swirl + downbeat push, real headless render)")
    func floretIsFlashSafe() throws {
        assertFlashSafe(name: "Floret", luma: try flashLuma("Floret"))
    }

    @Test("Glaze is flash-safe (mv_warp feedback + GLAZE.6 glossy bloom, real headless render)")
    func glazeIsFlashSafe() throws {
        assertFlashSafe(name: "Glaze", luma: try flashLuma("Glaze"))
    }

    @Test("Filigree is flash-safe (particle physarum trail, real headless render)")
    func filigreeIsFlashSafe() throws {
        // Settle the trail (150 frames) so we measure the steady accent, not the grow-in.
        assertFlashSafe(name: "Filigree", luma: try flashLuma("Filigree", settle: 150))
    }

    @Test("Mitosis is flash-safe (reaction–diffusion cell colony, real headless render)")
    func mitosisIsFlashSafe() throws {
        // ~25 s — the growth-to-crowded + dissolve are the largest luma swings; measure across them.
        assertFlashSafe(name: "Mitosis", luma: try flashLuma("Mitosis", frames: 1500))
    }

    @Test("Cytokinesis is flash-safe (explicit-cell division, real headless render)")
    func cytokinesisIsFlashSafe() throws {
        assertFlashSafe(name: "Cytokinesis", luma: try flashLuma("Cytokinesis", frames: 1500))
    }

    // MARK: - Flash-specific drive + reducer

    /// Render `name` through the shared harness on the synthetic worst-case beat+stem train,
    /// reduced to per-frame WCAG relative luminance (the flash signal). `frames` (when set)
    /// tiles the 3 s train to a longer window for the slow-cycle particle presets.
    private func flashLuma(_ name: String, settle: Int = 0, frames: Int? = nil) throws -> [Double] {
        let beat = FlashHarnessSupport.worstCaseBeatTrain()
        let stem = FlashHarnessSupport.worstCaseStemTrain()
        let f = frames.map { tile(beat, $0) } ?? beat
        let s = frames.map { tile(stem, $0) } ?? stem
        return try harness.render(preset: name, features: f, stems: s, settle: settle) {
            FlashHarnessSupport.meanRelativeLuminance($0)
        }
    }

    private func tile<T>(_ a: [T], _ n: Int) -> [T] { (0..<n).map { a[$0 % a.count] } }

    // MARK: - Assertion (shared)

    /// Print the per-preset evidence line and assert flash-safety. Fails LOUD on a static
    /// render — a static frame is never asserted "safe" (that would be a vacuous pass for a
    /// safety gate); it means the harness did not reach the preset's real response.
    private func assertFlashSafe(name: String, luma: [Double]) {
        let report = FlashAnalyzer.analyze(relativeLuminance: luma, fps: FlashHarnessSupport.fps)
        let lo = luma.min() ?? 0, hi = luma.max() ?? 0
        let range = hi - lo
        let mean = luma.reduce(0, +) / Double(max(luma.count, 1))
        let responded = range >= FlashHarnessSupport.responsiveLumaRange

        print(String(
            format: "[flash-safety] %@: %@ | peak %.2f flashes/s (%d transitions) — %@ | luma %.3f…%.3f (Δ%.3f, mean %.3f) [limit 3.0]",
            name, responded ? "MEASURED" : "UNMEASURED(static)",
            report.peakFlashesPerSecond, report.transitionCount,
            report.isSafe ? "SAFE" : "UNSAFE", lo, hi, range, mean))

        #expect(
            responded,
            """
            '\(name)' rendered static (Δ\(String(format: "%.4f", range))) under the worst-case beat+stem train — \
            the harness is not reaching its real multi-pass response, so the measurement is INVALID (not safe). \
            Fix the harness setup; do not weaken this guard.
            """)
        #expect(
            report.isSafe,
            """
            '\(name)' peaks at \(String(format: "%.2f", report.peakFlashesPerSecond)) flashes/s (limit 3) under a \
            \(String(format: "%.1f", FlashHarnessSupport.accentHz)) Hz worst-case beat train — exceeds Harding/WCAG 2.3.1. \
            P1 safety finding: bring to Matt, do NOT tune away (the certified motion was hand-built safe, D-157/D-158).
            """)
    }
}
