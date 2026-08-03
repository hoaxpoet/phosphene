// MeniscusDrops — the source's drop placement, ported (MEN.2b).
//
// This is the mechanism `MENISCUS_PLAN.md` §3 calls "a cepstrum-like transform, and it
// is inaudible": the source takes the FFT magnitude spectrum, runs a short DFT **over
// the spectrum** (not over time), and reads each bin's real and imaginary parts as an
// (x, y) position on the height-field grid, with the bin's magnitude setting the impact
// force. Harmonic spacing in the spectrum therefore decides where drops land.
//
// WHY IT IS PORTED AT ALL, given §5 names it as the thing Meniscus REPLACES at MEN.3:
// because it sets the distribution the wave sim was tuned against — how many drops per
// second, how spread out, how hard — and the interference structure in reference `07`
// only appears at a certain drop density. The faithful base is how we learn what density
// the surface needs BEFORE changing what decides the drops (§2 reason 2).
//
// WRITTEN FROM BEHAVIOUR, NOT TRANSCRIBED (D-116 bullet 1). A DFT over a magnitude
// spectrum is textbook; what is ported is the *use* of it as a 2-D placement, and the
// impact shape.
//
// SPECTRUM ACCESS. `ParticleGeometry.update` carries only 6 band energies, so the
// obvious reading is that this needs a new engine surface. It does not: `FFTProcessor`
// publishes its 512 magnitudes through a `.storageModeShared` UMA buffer, the same
// physical memory the fragment stages already bind at slot 1. Holding a reference to it
// and reading `contents()` on the CPU costs nothing and adds no contract — no protocol
// change, no per-frame copy, no tick bridge.

import Foundation
import Metal

// MARK: - MeniscusDrops

/// Places drops on the grid from the spectrum, and stamps their impacts into a height
/// field. Owns no storage beyond its own smoothing state.
struct MeniscusDrops {

    /// Bins in the DFT-over-spectrum. The source uses 30; each bin yields one candidate
    /// drop, so this also sets the maximum drops considered per frame.
    static let binCount = 30

    /// Per-bin smoothed magnitude, so a drop's force reflects a sustained harmonic
    /// rather than one frame's noise.
    private var smoothed = [Float](repeating: 0, count: binCount)
    /// Running mean of the per-bin magnitude — the deviation reference. The source
    /// thresholds against an absolute level; on AGC-normalised input that is FA #31, so
    /// placement fires on a bin rising ABOVE ITS OWN mean instead (D-026).
    /// Per-bin (real, imag) from this frame's transform — the placement coordinates.
    private var components = [SIMD2<Float>](repeating: .zero, count: binCount)

    /// Diagnostic: VISIBLE drops stamped on the most recent step (see `dropVisibleForce`).
    private(set) var lastDropCount = 0
    /// Diagnostic: summed force stamped on the most recent step.
    private(set) var lastDropForce: Float = 0

    // MARK: - Per frame

    /// Read the spectrum, place drops, and stamp them into `field` (a `side × side`
    /// height grid, row-major, toroidal).
    ///
    /// - Parameters:
    ///   - spectrum: 512 FFT magnitudes, CPU-readable UMA memory.
    ///   - field: the height field to stamp into, mutated in place.
    ///   - side: grid resolution per side.
    ///   - dt: frame delta, seconds.
    ///   - configuration: drop force / gate tunables.
    mutating func step(
        spectrum: UnsafeBufferPointer<Float>,
        field: inout [Float],
        side: Int,
        dt: Float,
        configuration: MeniscusConfiguration
    ) {
        lastDropCount = 0
        lastDropForce = 0
        guard side > 4, spectrum.count >= 64 else { return }

        // The source runs its transform over the low half of the spectrum, where
        // harmonic structure actually lives; the top octaves are mostly noise floor and
        // would only jitter the placement.
        let usable = min(spectrum.count / 2, 256)
        let alpha = 1 - exp(-dt / 0.06)          // per-bin attack/decay

        // Two passes: the first fills `smoothed`, the second stamps — the across-bin
        // normaliser needs every bin's magnitude before any of them can be scored.
        for bin in 0..<Self.binCount {
            let omega = 2 * Float.pi * Float(bin + 1) / Float(usable)
            var real: Float = 0, imag: Float = 0
            for index in 0..<usable {
                let phase = omega * Float(index)
                real += spectrum[index] * cos(phase)
                imag += spectrum[index] * sin(phase)
            }
            let norm = 1 / Float(usable)
            real *= norm; imag *= norm
            components[bin] = SIMD2<Float>(real, imag)
            smoothed[bin] += ((real * real + imag * imag).squareRoot() - smoothed[bin]) * alpha
        }
        var frameMean: Float = 0
        for value in smoothed { frameMean += value }
        frameMean /= Float(Self.binCount)
        // ABSOLUTE LEVEL GATE, separate from the across-bin normaliser.
        //
        // Dividing by `frameMean` alone is unsound when there is nothing to divide: a
        // structureless spectrum makes every DFT bin ~0, so every ratio comes out ~1 and
        // the field gets stamped at full force everywhere — silence rendering as a storm.
        // The flat-spectrum test caught exactly that. Level scales the whole drive by how
        // much transform energy actually exists, so no signal means no drops, while the
        // relative structure between bins still decides placement when there IS signal.
        let level = min(1, frameMean / configuration.dropLevelReference)

        for bin in 0..<Self.binCount {
            let real = components[bin].x, imag = components[bin].y
            // Real and imaginary parts become a position; the magnitude becomes
            // force. This is the whole trick, and why the placement is inaudible
            // but not arbitrary — it responds to harmonic SPACING.

            // FORCE IS THE BIN'S MAGNITUDE. Two earlier attempts got this wrong by more
            // than 100x, both for the same reason: I introduced a per-bin DEVIATION
            // (magnitude relative to that bin's own running mean) to satisfy D-026, then
            // tuned around the result.
            //
            // D-026 / FA #31 forbids absolute THRESHOLDS on AGC-normalised energy. A
            // force proportional to magnitude is not a threshold, so the rule never
            // applied here — and the ratio actively broke the port: dividing by a small
            // per-bin mean makes a QUIET bin produce a huge value, so every bin fired
            // every frame (297-522/s, then 713-838/s). §3 says plainly that the bin's
            // magnitude sets the impact force. Taking it literally is both faithful and
            // simpler, and it restores the distribution the wave sim was tuned against —
            // which is the entire reason §2 reason 2 says to port this at all.
            // …normalised ACROSS BINS within the frame, not per-bin over time.
            //
            // Raw magnitudes scale with how loud the track is: measured 9.7 drops/s on
            // quiet jazz against 569/s on loud electronic, from identical code. Dividing
            // by the frame's own mean bin magnitude removes that while PRESERVING the
            // relative structure between bins — which is the harmonic spacing the whole
            // placement keys on. The earlier per-bin-over-time ratio destroyed exactly
            // that structure, which is why it fired everything.
            let drive = (smoothed[bin] / max(frameMean, 1e-6)) * level
            guard drive > 1e-4 else { continue }

            // Real/imag → grid cell. They are signed and roughly balanced, so mapping
            // through a tanh-like squash keeps drops off the margins without clipping a
            // whole family of harmonics onto the edge.
            let unitX = 0.5 + 0.5 * tanhApprox(real * configuration.dropSpread)
            let unitY = 0.5 + 0.5 * tanhApprox(imag * configuration.dropSpread)
            let col = min(side - 1, max(0, Int(unitX * Float(side))))
            let row = min(side - 1, max(0, Int(unitY * Float(side))))

            let force = min(drive * configuration.dropForce, configuration.dropForceCeiling)
            stamp(&field, side: side, col: col, row: row, force: force)
            lastDropForce += force
            // Counted only when the impact is big enough to SEE. Diagnostic, not a
            // behavioural gate: every bin above still contributes its force. This is the
            // number the rate assertion reads, because "drops per second" only means
            // anything for impacts a viewer can distinguish.
            if force > configuration.dropVisibleForce { lastDropCount += 1 }
        }
    }

    mutating func reset() {
        for i in smoothed.indices { smoothed[i] = 0; components[i] = .zero }
        lastDropCount = 0
        lastDropForce = 0
    }

    // MARK: - Impact

    /// A 3×3 stencil, as the source uses — centre-weighted so the impact is a narrow
    /// tall spike rather than a broad heave. Reference `04`: "much taller than it is
    /// wide. Impacts read as punctuation; broad heaves read as mush."
    ///
    /// Toroidal, matching the sim: a drop near an edge wraps rather than clipping.
    private func stamp(_ field: inout [Float], side: Int, col: Int, row: Int, force: Float) {
        let weights: [Float] = [0.5, 0.8, 0.5,
                                0.8, 1.0, 0.8,
                                0.5, 0.8, 0.5]
        var weightIndex = 0
        for dy in -1...1 {
            let wrappedRow = ((row + dy) % side + side) % side
            for dx in -1...1 {
                let wrappedCol = ((col + dx) % side + side) % side
                field[wrappedRow * side + wrappedCol] -= force * weights[weightIndex]
                weightIndex += 1
            }
        }
    }

    /// `tanh` without importing Foundation's transcendental into a hot loop; the exact
    /// curve does not matter, only that it squashes monotonically to ±1.
    private func tanhApprox(_ x: Float) -> Float {
        let clamped = max(-3, min(3, x))
        let sq = clamped * clamped
        return clamped * (27 + sq) / (27 + 9 * sq)
    }
}
