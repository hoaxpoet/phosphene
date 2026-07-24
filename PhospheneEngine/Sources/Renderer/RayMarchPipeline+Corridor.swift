// RayMarchPipeline+Corridor — FLY.12 corridor-following steering.
//
// WHY (BUG-071 / the "navigate the gaps" ask). Fractal Fly-By's travel magnifies
// toward a FIXED point in the fractal, straight through whatever is in the way.
// When that path runs through a channel it threads it and reads beautifully; when
// it runs through solid it plows through the wall — Matt's "pushing through walls
// … very disorienting." No parameter fixes it (the scale was swept and the peak
// frame stays dense mush): the fix has to be about the PATH, not a constant.
//
// So the camera actively SEEKS OPEN SPACE. Each frame, read the previous frame's
// depth buffer, find where the frame is most open (the visible channel / void),
// and drift the lateral travel offset toward it — heavily smoothed, so it is a
// calm glide down a corridor, not a twitchy search. Matt's direction: "actively
// seek open space, calmer, always a corridor ahead."
//
// The depth read is of the PREVIOUS frame's `gbuffer0` (its command buffer has
// long since completed), so there is no GPU stall; the resulting one-frame
// latency is invisible under the slow smoothing.

import Foundation
import Metal
import simd

extension RayMarchPipeline {

    /// Read the last frame's depth, steer the travel offset toward the most-open
    /// region, publish it in `sceneUniforms.presetSteer`. Called at the top of a
    /// frame, before the new G-buffer pass overwrites `gbuffer0`.
    func steerCorridor() {
        guard corridorSteerEnabled, let depthTex = gbuffer0 else {
            sceneUniforms.presetSteer = .zero
            return
        }
        let texW = depthTex.width, texH = depthTex.height
        guard texW > 0, texH > 0 else { return }

        // gbuffer0 is .rg16Float, shared storage (UMA) → CPU-readable, no blit.
        // R = normalized depth [0,1); 1.0 = miss = the enclosed void = the opening.
        if corridorScratch.count != texW * texH * 2 {
            corridorScratch = [UInt16](repeating: 0, count: texW * texH * 2)
        }
        corridorScratch.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            depthTex.getBytes(base,
                              bytesPerRow: texW * 4,
                              from: MTLRegionMake2D(0, 0, texW, texH),
                              mipmapLevel: 0)
        }

        // Depth-weighted centroid of the OPEN regions. depth^3 weights the far
        // openings strongly, so the camera aims at the deepest visible channel;
        // if the frame is all wall, it still aims at the least-solid direction and
        // so pulls OUT of dense pockets.
        var sumW: Float = 0, sumU: Float = 0, sumV: Float = 0
        let step = max(8, texW / 96)
        var yy = 0
        while yy < texH {
            let row = yy * texW
            var xx = 0
            while xx < texW {
                let depth = Float(Float16(bitPattern: corridorScratch[(row + xx) * 2]))
                let weight = depth * depth * depth
                sumW += weight
                sumU += weight * (Float(xx) / Float(texW - 1) * 2 - 1)
                sumV += weight * (Float(yy) / Float(texH - 1) * 2 - 1)
                xx += step
            }
            yy += step
        }
        guard sumW > 1e-4 else {
            sceneUniforms.presetSteer = SIMD4(steerX, steerY, 0, 0)
            return
        }

        // Opening centroid offset from screen centre, in [-1, 1]. Screen v points
        // down, world up is +cameraUp, so v is negated. Sign of the whole nudge is
        // set by CORRIDOR_GAIN and verified against rendered frames.
        let cu = sumU / sumW
        let cv = sumV / sumW
        let targetX = cu * RayMarchPipeline.corridorGain
        let targetY = -cv * RayMarchPipeline.corridorGain

        // Calm: a slow EMA so the camera eases toward the opening over ~1.5 s
        // rather than snapping frame-to-frame.
        let alpha = RayMarchPipeline.corridorAlpha
        steerX += (targetX - steerX) * alpha
        steerY += (targetY - steerY) * alpha

        // Clamp so a persistent opening can't walk the offset off to infinity.
        let lim = RayMarchPipeline.corridorLimit
        steerX = min(max(steerX, -lim), lim)
        steerY = min(max(steerY, -lim), lim)

        sceneUniforms.presetSteer = SIMD4(steerX, steerY, 0, 0)
    }

    /// Reset steering on preset (re)apply so a new track starts centred.
    public func resetCorridorSteer() {
        steerX = 0
        steerY = 0
        sceneUniforms.presetSteer = .zero
    }

    static let corridorGain: Float  = 0.9    // how hard to lean toward the opening
    static let corridorAlpha: Float = 0.03   // EMA per frame → ~1.5 s ease (calm)
    static let corridorLimit: Float = 1.2    // max lateral offset
}
