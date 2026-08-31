// ArachneState+SegmentRollover — restart the foreground build cycle a beat after
// the segment completes.
//
// This is what survives of the V.7.7C.2 §5.12 "saturated background pool"
// (D-095), deleted at RECON.20. That design snapshotted the finished foreground
// hero into a 2-slot background pool and crossfaded opacities across a 1 s
// window. The shader side was never built — the pool loop shipped as
// `for (wi = 1; wi < 1; wi++)` and was retired at V.7.7C.3 — so the pool, its
// opacity ramps and its eviction helper mutated state nothing ever rendered.
//
// One real behaviour was buried in that machinery, and it is preserved here
// unchanged: **one second after the completion event, the foreground build
// cycle restarts** — fresh build state, a newly picked polygon, a recomputed
// spiral chord table, and the per-segment spider cooldown re-armed. Without it
// Arachne builds one web and stops until the orchestrator resets it.
//
// The 1 s delay is deliberate and preserved exactly: it is the pause between a
// finished web and the next one starting to draw.

import Foundation

extension ArachneState {

    /// Seconds between the completion event and the next build cycle starting.
    /// Was `migrationCrossfadeDurationSeconds`; the value is unchanged.
    static let segmentRolloverDelaySeconds: Float = 1.0

    /// Open the rollover clock. Called from `advanceStablePhase` immediately
    /// after `_presetCompletionEvent.send()`. No-op if one is already running.
    func beginSegmentRollover() {
        guard segmentRolloverElapsed == nil else { return }
        segmentRolloverElapsed = 0
    }

    /// Advance the rollover clock by `dt` (called from `_tick`, lock held) and
    /// start the next build cycle when the delay elapses.
    func advanceSegmentRollover(dt: Float) {
        guard var elapsed = segmentRolloverElapsed else { return }
        elapsed += dt
        if elapsed >= Self.segmentRolloverDelaySeconds {
            startNextBuildCycle()
            segmentRolloverElapsed = nil
        } else {
            segmentRolloverElapsed = elapsed
        }
    }

    /// Begin a fresh foreground build cycle. The orchestrator may also call
    /// `reset()` later — both paths are idempotent.
    private func startNextBuildCycle() {
        var bs = ArachneBuildState.zero()
        bs.radialCount = buildState.radialCount
        bs.spiralRevolutions = buildState.spiralRevolutions
        bs.radialDrawOrder = ArachneState.computeAlternatingPairOrder(
            radialCount: bs.radialCount
        )
        // Re-pick polygon for variety.
        let polygon = ArachneState.selectPolygon(rng: &rng)
        bs.anchors = polygon.anchors
        bs.anchorBlobIntensities = Array(repeating: 0, count: polygon.anchors.count)
        bs.bridgeAnchorPairFirst = polygon.bridgeFirst
        bs.bridgeAnchorPairSecond = polygon.bridgeSecond
        buildState = bs
        recomputeSpiralChordTable()
        // Per-segment spider cooldown re-arms when the build cycle rolls over.
        spiderFiredInSegment = false
    }
}
