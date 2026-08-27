// SkeinState+TailResolve — the per-frame tail resolution the fragment used to do per pixel
// (BUG-107).
//
// Split from `SkeinState.swift` at its 300-line type-body cap. Pure, static and side-effect free:
// given a header and the breakpoint ring, produce the `tailSamples` painter states the marks
// fragment reads. `SkeinLineCostTests` calls this directly to build a synthetic uniform buffer,
// which is what makes a known painter state renderable offline at all.

import Foundation
import simd

extension SkeinState {

    // MARK: - Tail resolution (BUG-107)

    /// Resolve the `tailSamples` painter states the fragment used to recompute per pixel.
    ///
    /// Entry `k` is the painter state at `tau − k·dτ`: its position on the natural path, and the
    /// colour / offset / start of the breakpoint in force at that painter clock. Mirrors
    /// `skeinPainterPos` and `skeinLineLookupAt` in Skein.metal — the two must stay in step, which
    /// is why both are small, closed-form and commented on each side.
    ///
    /// Float (not Double) arithmetic throughout, to stay as close as the platforms allow to what
    /// the shader was computing. MSL's `sin` is a fast approximation where Swift's is correctly
    /// rounded, so positions can differ in the last ulp or so — sub-pixel, and the alternative
    /// (recomputing 246 transcendentals per fragment) is what this is fixing.
    static func resolveTail(into ptr: UnsafeMutablePointer<SkeinTailGPU>,
                            header: SkeinHeaderGPU,
                            breaks: [SkeinBreakGPU]) {
        let tau = header.painterTau
        let dtau = max(header.painterTauStep, Self.tauStepFloor)
        let phx = header.seedPhaseX, phy = header.seedPhaseY
        let ringCount = min(breaks.count, Self.maxColorBreaks)

        for k in 0..<Self.tailSamples {
            let sampleTau = tau - Float(k) * dtau
            let pos = painterPosition(t: sampleTau, phx: phx, phy: phy)

            // skeinLineLookupAt: ascending ring, last breakpoint at or before `ct` wins; with no
            // ring at all the current pour applies with no offset and a start that can never match
            // (so no segment is suppressed as a bridge).
            var col = SIMD3<Float>(header.lineColR, header.lineColG, header.lineColB)
            var off = SIMD2<Float>(0, 0)
            var start: Float = -1e30
            if ringCount > 0 {
                var sel = breaks[0]
                for i in 1..<ringCount {
                    let bk = breaks[i]
                    if bk.tauStart <= sampleTau { sel = bk } else { break }
                }
                col = SIMD3<Float>(sel.colR, sel.colG, sel.colB)
                off = SIMD2<Float>(sel.offX, sel.offY)
                start = sel.tauStart
            }
            ptr[k] = SkeinTailGPU(
                posX: pos.x,
                posY: pos.y,
                colR: col.x,
                colG: col.y,
                colB: col.z,
                offX: off.x,
                offY: off.y,
                start: start
            )
        }
    }

    /// Mirror of `skeinPainterPos` in Skein.metal — three summed sinusoids per axis.
    static func painterPosition(t tau: Float, phx: Float, phy: Float) -> SIMD2<Float> {
        let x = 0.5
            + 0.300 * sin(0.220 * tau + 0.0 + phx)
            + 0.110 * sin(0.950 * tau + 1.7 + phx)
            + 0.045 * sin(2.300 * tau + 4.2 + phx)
        let y = 0.5
            + 0.280 * cos(0.190 * tau + 2.3 + phy)
            + 0.120 * cos(1.070 * tau + 5.1 + phy)
            + 0.040 * cos(2.620 * tau + 0.9 + phy)
        return SIMD2<Float>(x, y)
    }
}
