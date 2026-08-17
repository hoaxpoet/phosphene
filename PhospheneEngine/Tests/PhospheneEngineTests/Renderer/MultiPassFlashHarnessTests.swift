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

    @Test("Volumetric Lithograph is flash-safe (ray_march kaleidoscope, steady-luminance rotation, real headless render)")
    func volumetricLithographIsFlashSafe() throws {
        // VL-PSY.5 removed the per-beat palette flare / ridge strobe; the downbeat
        // now drives a monotonic ROTATION ratchet (geometry, not luminance), so the
        // frame's global brightness should hold steady under the worst-case beat
        // train. Measured, not assumed — this is the cert gate proving it.
        assertFlashSafe(name: "Volumetric Lithograph", luma: try flashLuma("Volumetric Lithograph"))
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

    @Test("Cymatic Resonance is flash-safe (vibrating-sand Chladni, real headless render)")
    func cymaticResonanceIsFlashSafe() throws {
        // Settle the sand into a figure (150 frames), then measure the steady beat response.
        // Total sand is conserved (grains move, never appear/disappear) → global luminance
        // is expected steady even on the worst-case beat train; this MEASURES that (CR.2 / D-199).
        assertFlashSafe(name: "Cymatic Resonance", luma: try flashLuma("Cymatic Resonance", settle: 150))
    }

    @Test("Witchlight is flash-safe (harmonic stroke + bounded head flare, real headless render)")
    func witchlightIsFlashSafe() throws {
        // The head flare is the risk this measurement exists for: the inspiration source
        // saturates most of the frame white on mid-band hits (anti-reference `12`), roughly a
        // fifth of its sampled frames. WITCHLIGHT_DESIGN §5 answers that with a CPU-side
        // budget — a hard 900 ms refractory, a fixed small extent, a >= 60 ms rise and a
        // bounded ceiling — designed up front rather than tuned down after. This gate is what
        // turns that budget from an intention into a number.
        //
        // Measured across the FULL 30 s trail cycle rather than a settled 3 s window. Witchlight
        // is a small bright subject on a large dark field, so its full-frame mean barely moves
        // in any 3 s slice — the geometry that makes it flash-safe is the same geometry that
        // makes it look static to a mean-luma responsiveness proxy. The honest window is the
        // one its subject actually occupies: the trail's own accumulation ramp from empty to
        // full, with the head flare firing throughout. Same reason Mitosis and Cytokinesis run
        // 1 500 frames — the harness tiles the 3 s train for slow-cycle particle presets.
        //
        // `harmonicMotion` is required on top: the shared train leaves tonal_phase_fifths at
        // zero, and Witchlight's pen is steered by nothing else.
        assertFlashSafe(name: "Witchlight",
                        luma: try flashLuma("Witchlight", frames: 1800, harmonicMotion: true))
    }

    @Test("Stave is flash-safe (spectral dispersion of the waveform, real headless render)")
    func stave_isFlashSafe() throws {
        // Wired at AUTHORING time, not at certification — the Meniscus lesson. Stave is
        // `certified: false` and this runs anyway.
        //
        // Stave reads ONLY the waveform buffer, so the worst case lives there rather than in
        // the shared FeatureVector train: `renderStave` gates broadband noise between full
        // scale and silence at the accent rate, which is the largest whole-frame luminance
        // swing the preset can make — the bands sum toward white and the fan opens together.
        // Real music never does this; a safe result here is a wide margin, not a near miss.
        assertFlashSafe(name: "Stave",
                        luma: try flashLuma("Stave", settle: 420, frames: 900))
    }

    @Test("Meniscus is flash-safe (continuous band drive + a drop on every beat, real headless render)")
    func meniscusIsFlashSafe() throws {
        // Meniscus reaches this harness because the single-pass gate correctly REFUSED it:
        // its fragment pass draws only the ground and sky, so the FeatureVector harness
        // renders it static and cannot flash-gate it. The surface itself is CPU geometry
        // (`MeniscusSurface`), which is what the multi-pass path drives.
        //
        // Two routes make this measurement load-bearing rather than ceremonial, and BOTH
        // arrived late in development: MEN.4c injects a continuous band-driven excitation
        // into the wave field, so whole-sheet brightness now rises with the music, and
        // MEN.3g puts a drop on EVERY grid beat. A worst-case beat train is precisely the
        // input that stacks those two.
        //
        // Whole-frame mean is a fair proxy here — unlike Witchlight's small bright subject,
        // the sheet occupies a large share of the frame — so the settled window is honest
        // and no tiling is needed.
        assertFlashSafe(name: "Meniscus", luma: try flashLuma("Meniscus", settle: 120))
    }

    // MARK: - Flash-specific drive + reducer

    /// Render `name` through the shared harness on the synthetic worst-case beat+stem train,
    /// reduced to per-frame WCAG relative luminance (the flash signal). `frames` (when set)
    /// tiles the 3 s train to a longer window for the slow-cycle particle presets.
    private func flashLuma(
        _ name: String, settle: Int = 0, frames: Int? = nil, harmonicMotion: Bool = false
    ) throws -> [Double] {
        // `harmonicMotion` layers the TONAL block onto the shared train — see
        // `FlashHarnessSupport.withHarmonicMotion`. Only for presets steered by it; the
        // shared train stays byte-identical for everyone else.
        let beat = harmonicMotion
            ? FlashHarnessSupport.withHarmonicMotion(FlashHarnessSupport.worstCaseBeatTrain())
            : FlashHarnessSupport.worstCaseBeatTrain()
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
