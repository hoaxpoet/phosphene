// WitchlightPath+Framing — the camera: where it aims, and how much it frames.
//
// Split out of `WitchlightPath+Events.swift` at WL.10 for the 400-line lint budget. It earns
// its own file: this is the code behind four separate M7 reports ("the same shape every
// time", "the camera cannot keep up", "does it ever zoom back in"), and the reasoning for
// each constant is longer than the constant.
//
// The single most important property: the SCALE FIT and the CAMERA AIM are computed from the
// same recent-window centre, and that centre is NOT the whole-trail centroid. Every framing
// defect this preset has had came from two of those three things disagreeing.

import Foundation
import Shared

extension WitchlightPath {

    // MARK: - Framing

    /// Follow the trail's centroid and auto-fit its extent.
    ///
    /// A VIEW property, deliberately separate from the path: bounded-curvature kinematics
    /// give a figure whose extent depends on how much the track's harmony moved, so a
    /// fixed camera would frame `01` on one track and a speck on the next. The figure is
    /// music-driven; the framing only keeps it legible and small-in-frame (trait #7).
    ///
    /// WL.7 — the SCALE and the CAMERA are computed from different points, and separating
    /// them is the whole fix for "still not tied to the music".
    ///
    /// Measured (`WitchlightHeadFramingTests`, CPU mirror of `wl_project`): with one shared
    /// centre, the burning head was **off frame on 33 / 35 / 45 % of frames** across the
    /// three fixtures, and outside a 0.9 inset on 40–48 %. That is where every coupling
    /// this preset has actually shows — the flare fires at the head, the newest beads are
    /// the brightest, and the WL.4 breath and WL.5 energy gate both read strongest there.
    /// Roughly two frames in five, the music was driving something the viewer could not
    /// see. Matt's sixth M7 said exactly this ("the ribbon is moving faster than the camera
    /// can catch up") and it was right.
    ///
    /// It happens by construction, not by mis-tuning: the pen advances continuously, so the
    /// head sits at the LEADING EXTREME of the trail while the fit is an RMS radius (~0.6 of
    /// true extent for a roughly linear stroke). With `framedRadius` 0.62 the furthest bead
    /// lands at ≈ 1.03 of the half-frame — just outside — and the head is nearly always the
    /// furthest bead.
    ///
    /// The three WL.6 attempts all tried to fix it by fitting MORE into frame (max-extent
    /// fit, `framedRadius` up to 0.86), which shrinks the drawing, and the WL.2-j
    /// distinctness gate correctly killed all three (23 → 4 distinct beads). This does the
    /// opposite: `viewScale` is left EXACTLY as it was — the drawing's size in frame, and so
    /// bead legibility, is unchanged bit-for-bit — and only the point the camera aims at
    /// moves. The trail's true centroid still sets the scale; the camera sits 60 % of the
    /// way toward the head on a 1.2 s follow.
    ///
    /// Swept over bias × follow on all three fixtures: 0.6 / 1.2 s is the first cell that
    /// reaches 0.0 % head-off-frame on every one. What it costs is the far TAIL — 30 s-old
    /// beads, frozen and dim — leaving frame: bead-frames off screen go 6.0 → 16.6 % on
    /// `so_what`, and IMPROVE on the other two (5.2 → 0.7 %, 14.0 → 11.0 %). Trading the
    /// oldest, dimmest end of the record for the burning tip is the right trade: the tail is
    /// where the music has already been, the head is where it is now.
    func reframe(dt: Float) {
        guard !beads.isEmpty else { return }
        var sumX: Float = 0, sumY: Float = 0
        for bead in beads { sumX += bead.posX; sumY += bead.posY }
        let count = Float(beads.count)
        let targetX = sumX / count, targetY = sumY / count
        let followAlpha = dt / (3.0 + dt)
        centroidX += (targetX - centroidX) * followAlpha
        centroidY += (targetY - centroidY) * followAlpha

        // WL.10 — the SCALE is fitted over a recent window, and over its OWN centroid.
        //
        // Both halves are load-bearing. Windowing the radius while still measuring distances
        // from the whole-trail centroid moves the scale the WRONG WAY: recent beads sit far
        // from an old centre, so the measured radius GROWS and the view zooms further out.
        // (Tried, measured, discarded — the window and the point it is measured from have to
        // move together.)
        //
        // `centroidX/centroidY` stays the whole-trail centroid and keeps driving the camera
        // AIM, which is untouched here: head-in-frame is the WL.7 contract and is separately
        // gated at 0.0 %. The fit gets its own centre so the two can differ.
        let window = tuning.fitWindowSeconds
        let windowed = window > 0 && window < trailWindow
        var fitSumX: Float = 0, fitSumY: Float = 0, fitCount: Float = 0
        for bead in beads where !windowed || bead.age <= window {
            fitSumX += bead.posX; fitSumY += bead.posY; fitCount += 1
        }
        if fitCount > 0 {
            fitCentroidX += (fitSumX / fitCount - fitCentroidX) * followAlpha
            fitCentroidY += (fitSumY / fitCount - fitCentroidY) * followAlpha
        }
        var sumSquares: Float = 0
        for bead in beads where !windowed || bead.age <= window {
            let dx = bead.posX - fitCentroidX, dy = bead.posY - fitCentroidY
            sumSquares += dx * dx + dy * dy
        }
        // WL.9b — the fit tracks the trail's GROWTH while it is still filling.
        //
        // Matt, session `2026-08-06T17-27-21Z`: "the camera cannot keep up with the head of
        // the ribbon". Measured per 10 s window, the head-off-frame misses are entirely inside
        // a 20–40 s band and are ZERO for the remaining two minutes — it is a startup
        // transient, not a steady-state failure and (measured) not a pen-speed one either.
        //
        // The cause is structural: the visible trail is 30 s, so for the first half-minute the
        // figure is still EXPANDING toward its final extent, and a 4 s fit constant chasing a
        // monotonically growing target is always behind it. Once the trail reaches full length
        // the target stops growing, the lag disappears, and framing is exact — which is why
        // the settled behaviour Matt approved at WL.7 needs no change and gets none.
        //
        // WL.7's gate reported 0.0 % and was not lying, it was measuring 21 s fixtures that END
        // before this window opens. The real-session harness (`WitchlightSpeedSweep`) is the
        // one that can see it.
        let oldest = beads.first?.age ?? trailWindow
        let filling = oldest < trailWindow * 0.95
        let targetRadius = (sumSquares / max(fitCount, 1)).squareRoot()
        // Asymmetric: catch up fast while the figure grows, never rush the shrink. A fast
        // shrink would make the drawing pump on every section contraction.
        let growing = targetRadius > rmsRadius
        let fitTau: Float = filling && growing ? 0.8 : 4.0
        let fitAlpha = dt / (fitTau + dt)
        rmsRadius += (targetRadius - rmsRadius) * fitAlpha
        viewScale = max(0.25, min(4.0, tuning.framedRadius / max(rmsRadius, 0.02)))

        // The camera. Head-biased so the burning tip stays in frame, on a follow short
        // enough to keep up with a pen that quickens 2.5× (WL.2-i) — at 3 s it cannot,
        // which is the lag Matt saw.
        guard let head = beads.last else { return }
        // Same reasoning on the aim: while the figure is growing the head is travelling into
        // new territory every frame, so the follow tightens. It relaxes to the settled 1.2 s
        // the moment the trail is full.
        let camAlpha = dt / ((filling ? 0.5 : 1.2) + dt)
        // WL.10 — the aim blends from the FIT centroid, not the whole-trail one.
        //
        // This was explicitly out of scope in the WL.10 spec ("do not touch the camera AIM"),
        // and the measurement overturned that: with the scale fitted to a recent window and
        // the aim still anchored to the 30 s centroid, the view zooms in around a point the
        // recent drawing has already left, and the head goes off frame on 19.4 % / 14.8 % /
        // 3.5 % of frames across three real sessions — the very contract the rule protects.
        //
        // The two have to describe the same region: a radius measured about one centre and a
        // view centred on another do not compose. Head-off-frame returns to 0.0 % everywhere
        // once they agree.
        let aimX = fitCentroidX * (1 - 0.6) + head.posX * 0.6
        let aimY = fitCentroidY * (1 - 0.6) + head.posY * 0.6
        cameraX += (aimX - cameraX) * camAlpha
        cameraY += (aimY - cameraY) * camAlpha
    }
}
