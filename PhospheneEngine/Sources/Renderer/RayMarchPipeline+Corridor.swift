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

        // FLY.13 — AVOID NEAR WALLS + CENTRE, not chase the far opening.
        //
        // The FLY.12 law aimed at the depth³-weighted centroid of the OPEN regions.
        // That chases the distant channel mouth while ignoring the wall you are
        // actually scraping — the camera grazed the near sides even with a channel
        // ahead (Matt: "still goes through walls"). The robust law is
        // collision-avoidance: measure how much NEAR geometry sits on the left vs
        // right (and top vs bottom) and ease AWAY from the closer side, which keeps
        // the camera centred in the channel.
        //
        // "Proximity" emphasises pixels whose depth is small (a wall in your face);
        // far/open pixels contribute ~0. Split the frame into left/right and
        // top/bottom halves and difference the proximities.
        let nearThresh = RayMarchPipeline.corridorNearThreshold
        var leftProx: Float = 0, rightProx: Float = 0
        var topProx: Float = 0, botProx: Float = 0
        var totalProx: Float = 0, sampleCount: Float = 0
        let step = max(8, texW / 96)
        var yy = 0
        while yy < texH {
            let row = yy * texW
            let isTop = yy < texH / 2
            var xx = 0
            while xx < texW {
                let depth = Float(Float16(bitPattern: corridorScratch[(row + xx) * 2]))
                let prox = max(0, nearThresh - depth)   // >0 only for near geometry
                if xx < texW / 2 { leftProx += prox } else { rightProx += prox }
                if isTop { topProx += prox } else { botProx += prox }
                totalProx += prox
                sampleCount += 1
                xx += step
            }
            yy += step
        }

        // FLY.13 DENSITY GOVERNOR — the deeper fix. The lateral steering can only
        // centre the camera in a channel that EXISTS; the scale-zoom travel
        // periodically plunges into regions of the Mandelbox that are dense in
        // every direction (no channel at all — the "still goes through walls"
        // frames are actually "no open space anywhere"). When the whole frame is
        // near-solid, the only escape is to pull the viewpoint BACK to a coarser
        // scale where channels reappear. `density` (0 = open, 1 = wall-to-wall)
        // is published in `presetSteer.z`; the shader eases the zoom base toward
        // its open end by that amount. Rate-limited like the lateral steer so the
        // scale never pops.
        let density = min(totalProx / max(sampleCount, 1) / nearThresh, 1)
        let densStep = RayMarchPipeline.corridorMaxStep
        smoothedDensity += min(max(density - smoothedDensity, -densStep), densStep)

        // Ease toward the CLEARER side (less near geometry). Sign verified against
        // rendered frames. Normalised so the response is scene-scale-independent.
        let denomX = max(leftProx + rightProx, 1e-3)
        let denomY = max(topProx + botProx, 1e-3)
        let targetX = (rightProx - leftProx) / denomX * RayMarchPipeline.corridorGain
        let targetY = (botProx - topProx) / denomY * RayMarchPipeline.corridorGain

        // RATE LIMIT — the anti-jerk guarantee. The camera offset may move at most
        // `corridorMaxStep` per frame, so no matter how violently the depth field
        // jumps (a fold event, a structural pop, a different track's dynamics) the
        // steering physically CANNOT lurch. This is what makes it track-independent:
        // FLY.12's EMA gain let a big target jump through in one frame, so the same
        // steering was calm on one track and lurched on another. A hard velocity
        // cap does not depend on the track.
        let maxStep = RayMarchPipeline.corridorMaxStep
        steerX += min(max(targetX - steerX, -maxStep), maxStep)
        steerY += min(max(targetY - steerY, -maxStep), maxStep)

        let lim = RayMarchPipeline.corridorLimit
        steerX = min(max(steerX, -lim), lim)
        steerY = min(max(steerY, -lim), lim)

        sceneUniforms.presetSteer = SIMD4(steerX, steerY, smoothedDensity, 0)
    }

    /// Reset steering on preset (re)apply so a new track starts centred.
    public func resetCorridorSteer() {
        steerX = 0
        steerY = 0
        smoothedDensity = 0
        sceneUniforms.presetSteer = .zero
    }

    static let corridorGain: Float          = 0.8     // full-swing steer at max imbalance
    static let corridorNearThreshold: Float = 0.45    // depth below this counts as a near wall
    static let corridorMaxStep: Float       = 0.006   // MAX offset change per frame (anti-jerk, track-independent)
    static let corridorLimit: Float         = 1.0     // max lateral offset
}
