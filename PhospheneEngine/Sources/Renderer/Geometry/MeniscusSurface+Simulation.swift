// MeniscusSurface+Simulation — the wave field's forcing and its serialization.
//
// Split from `MeniscusSurface` at MEN.4c purely for size: that file holds the Metal state
// (buffers, pipelines, camera) and this one holds the two things that run per frame and
// carry the preset's audio behaviour — how the music excites the field, and how the field
// becomes the serpentine line strip the vertex shader draws.
//
// Read `driveContinuously` first. It is the preset's PRIMARY audio driver per CLAUDE.md's
// audio hierarchy; the beat-locked drops in `MeniscusStemDrops` are the accent on top.

import Foundation
import Metal
import Shared

// MARK: - Simulation

extension MeniscusSurface {

    /// Continuously excite the wave field from the band envelopes (MEN.4c).
    ///
    /// INTO THE SIM STATE, deliberately. The MEN.2a swell was added at DISPLAY time and
    /// never entered the field, which meant two things: the sim itself never moved with the
    /// music, and the swell could not INTERFERE with the drops — so §1's "the ripples that
    /// spread from each impact and interfere with one another" was never actually
    /// happening. The tether gate caught it: with a display-only swell the surface's own
    /// RMS correlated r=+0.136 with the music, essentially untethered.
    ///
    /// Three travelling wavelengths, one per band, injected as a small per-frame
    /// displacement. Amplitude is deliberately modest — this is a swell the drops punctuate,
    /// not a competitor to them — and it is scaled by `dt` so the excitation is
    /// frame-rate-independent.
    internal func driveContinuously(dt: Float) {
        let side = configuration.gridN
        guard side > 4 else { return }
        let span = Float(max(side - 1, 1))
        let clock = elapsed
        let gain = configuration.continuousDrive * dt
        guard gain > 0 else { return }
        for row in 0..<side {
            let rowFrac = Float(row) / span
            let rowBase = row * side
            for col in 0..<side {
                let colFrac = Float(col) / span
                let long = sin(colFrac * 2.1 + clock * 0.31) * cos(rowFrac * 1.6 - clock * 0.23)
                let mid = sin((colFrac * 5.3 - rowFrac * 4.1) + clock * 0.47)
                let fine = cos((colFrac * 9.7 + rowFrac * 8.3) - clock * 0.63)
                current[rowBase + col] += gain
                    * (bandSwell.x * long + 0.6 * bandSwell.y * mid + 0.35 * bandSwell.z * fine)
            }
        }
    }

    /// Walk the grid in serpentine row order and write the path samples the vertex
    /// shader consumes: display height (sim + swell) and the slope term the shading reads.
    ///
    /// The slope is `h − s`, where `s` is a one-sample-lagged IIR of the height taken ALONG
    /// THE PATH — the source's own construction (`MENISCUS_PLAN.md` §3), and the reason
    /// crests read near-white while the trough two samples away reads near-black (trait T3,
    /// reference `07`).
    internal func serializeSerpentinePath(intensity: Float) {
        // THE SWELL IS THE LIVING SURFACE (MEN.4c), not the silence state it started as.
        //
        // MEN.2a introduced it as a placeholder and MEN.3d then faded it OUT as the music
        // rose — which left the surface with NO continuous audio-driven motion during
        // music, only discrete drop events. That inverts CLAUDE.md's central rule
        // ("continuous energy is the DEFAULT PRIMARY DRIVER; visuals driven primarily by
        // beat detections feel out of sync"), and Matt's tenth-round verdict was the exact
        // phrase it predicts: "feels less tethered to the music". Cutting drop density
        // made it worse, which is what ruled density out. §9 MEN.4c.
        //
        // The excitation now goes into the SIM (`driveContinuously`) so the sheet breathes
        // with the music and the drops interfere with it; what remains here is the display
        // swell, whose floors are the original silence amplitudes so §4 and D-037 survive
        // untouched and the music is purely additive on top.
        let swellGate: Float = 1
        let side = configuration.gridN
        guard side > 0 else { return }
        let lag = configuration.slopeLag
        let swell = configuration.swellAmplitude
        let clock = elapsed
        let span = Float(max(side - 1, 1))

        let ptr = pointBuffer.contents().bindMemory(to: MeniscusPoint.self, capacity: pointCount)
        var smoothed: Float = 0
        var index = 0

        for row in 0..<side {
            let rowBase = row * side
            let reversed = (row % 2) == 1
            let rowFrac = Float(row) / span
            for step in 0..<side {
                let col = reversed ? (side - 1 - step) : step
                let colFrac = Float(col) / span

                // MEN.2a PLACEHOLDER ONLY (task 6) — a standing swell added at DISPLAY
                // time, never into the sim state, so the wave field MEN.2b inherits is
                // untouched and this is one expression to delete.
                //
                // THREE wavelengths, not one. A single long wave gives the plate a
                // smooth tilt with near-constant slope everywhere, and a constant slope
                // is a flat grey sheet under T3's shading — "a soft, evenly-lit version
                // of this looks like fabric, not water" (reference README, `07`). The
                // mid and short terms put crests and troughs a couple of samples apart
                // so the shading has something to resolve. Temporal rates stay slow:
                // §7 R6's recovery for a swell that reads frozen is MORE SPATIAL
                // VARIATION, never a faster swell.
                // Each wavelength answers to its own band, and each keeps a floor so the
                // silence state (§4) survives: long swell <- bass, mid ripple <- mids,
                // fine chop <- treble. The bands are scaled to comparable range first
                // (mid x3, treble x8) because treble energy is ~50x smaller than bass on
                // real music — the GLAZE.8 finding, applied as a gain rather than ignored.
                // The floors are the ORIGINAL silence amplitudes, so the §4 silence state
                // is preserved exactly and the music is purely ADDITIVE on top of it. A
                // first attempt used lower floors and immediately tripped the D-037 motion
                // gate at silence — the rule is a floor on the surface, not on the music.
                let longAmp = 1.00 + 2.0 * bandSwell.x
                let midAmp = 0.55 + 1.6 * bandSwell.y
                let fineAmp = 0.30 + 1.3 * bandSwell.z
                let swellTerm = swell * swellGate * (
                    longAmp * sin(colFrac * 2.1 + clock * 0.31) * cos(rowFrac * 1.6 - clock * 0.23)
                    + midAmp * sin((colFrac * 5.3 - rowFrac * 4.1) + clock * 0.19)
                    + fineAmp * cos((colFrac * 9.7 + rowFrac * 8.3) - clock * 0.27))

                // §5's loudness row applied where it belongs: to WAVE AMPLITUDE, so the
                // whole sheet is calmer in quiet passages and choppier in loud ones.
                // Scaling only per-drop force (the first attempt) barely moved the needle
                // — per-hit deviation variance swamps it, r=0.13. The sheet's amplitude is
                // a global, visible property and it is what §5 actually names.
                let height = (current[rowBase + col] + swellTerm) * intensity
                smoothed += (height - smoothed) * lag
                ptr[index] = MeniscusPoint(height: height, slope: height - smoothed)
                index += 1
            }
        }
    }
}
