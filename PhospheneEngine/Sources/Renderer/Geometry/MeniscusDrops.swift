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

    /// The source's smoothed AGC level (`amp_`) — a temporally lagged energy scale.
    private var level: Float = 0
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

        let fps = max(1 / max(dt, 1e-5), 1)
        // Source constants, read from the preset file (Matt, 2026-08-03) rather than
        // guessed. Four rounds of guessing missed the rate by 100x+; every value below
        // is now sourced.
        //   dec_f   = pow(0.8, 30/fps)   — decay on the accumulated components
        //   dec_med = 1 - 0.06*30/fps    — decay on the AGC level
        let decF = pow(0.8, 30 / fps)
        let decMed = 1 - 1.8 / fps

        // 1. AGC THE SPECTRUM. The step my port was missing entirely, and the reason raw
        //    magnitude came out track-loudness dependent while a per-frame across-bin
        //    normaliser came out scale-free. The source subtracts the spectrum's mean and
        //    divides by a TEMPORALLY SMOOTHED energy level — loudness-independent without
        //    being scale-free, because the level lags rather than tracking each frame.
        // The AGC statistics run over `reg01` taps — 126 for a 45x45 grid — while the
        // transform below uses only `flen` = 30. Using 30 for both makes the level about
        // 2x too small and the normalised spectrum correspondingly too large.
        let taps = Self.binCount
        let reg01Count = max(Int(Float(side * side) / 16), taps)
        let agcStride = max(spectrum.count / reg01Count, 1)
        var sum: Float = 0
        var energy: Float = 0.01                    // the source's 0.01 seed
        for tap in 0..<reg01Count {
            let magnitude = spectrum[min(tap * agcStride, spectrum.count - 1)]
            sum += magnitude
            energy += magnitude * magnitude
        }
        sum /= Float(reg01Count)
        let reg01 = Float(reg01Count)
        level = level * decMed + 600 * (1 - decMed) * energy.squareRoot() / reg01
        let stride = max(spectrum.count / taps, 1)
        guard level > 1e-6 else { return }

        // 2. DFT OVER THE NORMALISED SPECTRUM, accumulated with decay. The accumulation
        //    is why a sustained harmonic keeps feeding one position instead of flickering.
        for bin in 0..<taps {
            var real: Float = 0
            var imag: Float = 0
            for tap in 0..<taps {
                let raw = spectrum[min(tap * stride, spectrum.count - 1)]
                let normalised = (raw - sum) / level
                let phase = 2 * Float.pi * Float(tap) / Float(taps) * Float(bin)
                real += cos(phase) * normalised
                imag += sin(phase) * normalised
            }
            components[bin] = SIMD2<Float>(components[bin].x * decF + real,
                                           components[bin].y * decF + imag)
        }

        // 3. STAMP. Only the FIRST HALF of the bins, from index 1 — the source loops
        //    `flen/2` starting at 1, so 15 drops per frame at most, not 30.
        for bin in 1..<(taps / 2) {
            let cx = components[bin].x
            let cy = components[bin].y
            // amp = 3 * |c|^2, gated at 0.02, force ∝ sqrt(amp) — so force is
            // proportional to |c|, and the gate is a hard threshold on the NORMALISED
            // transform output (not on AGC'd band energy, so FA #31 does not apply).
            let amp = 3 * (cx * cx + cy * cy)
            guard amp > configuration.dropGate else { continue }
            let force = (60 / fps) * amp.squareRoot() * configuration.dropForce

            // Position by plain modulo wrap — not the tanh squash I invented.
            for dy in -1...1 {
                for dx in -1...1 {
                    let col = Self.wrap((cx + 0.5) * Float(side) + Float(dx), side)
                    let row = Self.wrap((cy + 0.5) * Float(side) + Float(dy), side)
                    // Stencil weight 1/(1 + dx^2 + dy^2): centre 1, edge 1/2, corner 1/3.
                    let weight = 1 / Float(1 + dx * dx + dy * dy)
                    field[row * side + col] -= force * weight
                }
            }
            lastDropForce += force
            if force > configuration.dropVisibleForce { lastDropCount += 1 }
        }
    }

    private static func wrap(_ value: Float, _ side: Int) -> Int {
        let wrapped = Int(value.rounded(.down)) % side
        return wrapped < 0 ? wrapped + side : wrapped
    }

    mutating func reset() {
        for i in components.indices { components[i] = .zero }
        level = 0
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
