// ArachneState+BackgroundWebs — V.7.7C.2 §5.12 saturated background pool (D-095).
//
// 1–2 fully-built saturated webs decorate the depth backdrop. They share the
// same SDF + drop recipe as the foreground but with `stage = .stable`, full
// drop counts, sag at the upper end of `kSag` range, and mild blur applied
// by post-process or in-shader.
//
// **Commit 2 owns the CPU-side state machine only.** The migration crossfade
// state advances; opacity values are stored on each `ArachneBackgroundWeb`.
// The shader does NOT yet read background webs in Commit 2 — Commit 3 wires
// the read.
//
// Migration on completion (V.7.7C.2 spec):
//   1. Foreground reaches `.stable` and fires `_presetCompletionEvent`.
//   2. `beginMigrationCrossfade()` opens a 1 s crossfade clock.
//   3. During the 1 s window:
//        - Foreground opacity ramps 1 → 0.4 (it joins the background pool).
//        - If pool at capacity (2), oldest ramps 1 → 0 over the same 1 s.
//   4. At end of 1 s, the foreground state is migrated into a new
//      `ArachneBackgroundWeb` (snapshot of webs[0]); the oldest pool entry
//      is removed when capacity is exceeded; foreground BuildState resets
//      and a new build cycle begins.

import Foundation
import simd

extension ArachneState {

    // MARK: - Migration crossfade constants

    /// Total seconds of the foreground→background crossfade.
    static let migrationCrossfadeDurationSeconds: Float = 1.0
    /// Steady-state opacity background webs settle at after migration (the
    /// foreground hero ramps 1 → 0.4 to join the pool).
    static let backgroundSteadyOpacity: Float = 0.4

    // MARK: - Migration entry point

    /// Open a fresh migration crossfade clock. Called from
    /// `advanceStablePhase` immediately after `_presetCompletionEvent.send()`.
    /// No-op if a migration is already in flight.
    func beginMigrationCrossfade() {
        guard migrationCrossfadeElapsed == nil else { return }
        migrationCrossfadeElapsed = 0
    }

    // MARK: - Migration tick

    /// Advance the migration crossfade by `dt`. Called from `_tick` (lock
    /// held). Updates `ArachneBackgroundWeb.opacity` for in-flight migrations
    /// and finalises the migration when the 1 s window completes.
    func advanceMigrationCrossfade(dt: Float) {
        guard var elapsed = migrationCrossfadeElapsed else { return }
        elapsed += dt
        let dur = Self.migrationCrossfadeDurationSeconds

        // During the window, oldest at-capacity background ramps 1 → 0; the
        // not-yet-migrated foreground would ramp 1 → 0.4 (Commit 3 reads its
        // opacity off this state — Commit 2 stores only).
        if elapsed >= dur {
            // Window complete: finalise.
            finaliseMigration()
            migrationCrossfadeElapsed = nil
        } else {
            let frac = max(0, min(1, elapsed / dur))
            // Oldest at capacity: ramp 1 → 0.
            if backgroundWebs.count >= Self.backgroundWebsCapacity,
               let oldestIdx = oldestBackgroundIndex() {
                backgroundWebs[oldestIdx].opacity = max(0, 1.0 - frac)
            }
            migrationCrossfadeElapsed = elapsed
        }
    }

    // MARK: - Finalise migration

    /// Snapshot the foreground hero (`webs[0]`) into a new
    /// `ArachneBackgroundWeb`, evict the oldest at capacity, and reset the
    /// build cycle so a fresh segment can begin without an explicit
    /// orchestrator-driven `reset()`.
    ///
    /// Note: the public `reset()` is the canonical entry; this internal
    /// finalisation reuses the same state-reset mechanics so a self-completing
    /// build cycle can roll over cleanly.
    private func finaliseMigration() {
        // Evict oldest if at capacity BEFORE appending.
        if backgroundWebs.count >= Self.backgroundWebsCapacity,
           let oldestIdx = oldestBackgroundIndex() {
            backgroundWebs.remove(at: oldestIdx)
        }

        // Snapshot foreground → background entry. Row 5 zeroed because
        // background webs do NOT carry build state (V.7.7C.2 contract).
        var snapshot = webs.first ?? .zero
        snapshot.buildStage = 0
        snapshot.frameProgress = 0
        snapshot.radialPacked = 0
        snapshot.spiralPacked = 0
        let entry = ArachneBackgroundWeb(
            webGPU: snapshot,
            birthTime: segmentClock,
            opacity: Self.backgroundSteadyOpacity
        )
        backgroundWebs.append(entry)

        // Begin a fresh foreground build cycle. The orchestrator may also
        // call `reset()` later — both paths are idempotent.
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

    // MARK: - Pool helpers

    /// Index into `backgroundWebs` of the oldest entry, or `nil` if empty.
    private func oldestBackgroundIndex() -> Int? {
        guard !backgroundWebs.isEmpty else { return nil }
        var oldest = 0
        for i in 1..<backgroundWebs.count
        where backgroundWebs[i].birthTime < backgroundWebs[oldest].birthTime {
            oldest = i
        }
        return oldest
    }
}
