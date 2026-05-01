// ArachneState+M7Diag — M7 diagnostic snapshot (V.7.5 Step 0).
//
// Activated by `-Xswiftc -DARACHNE_M7_DIAG` (DEBUG only). Logs once per
// "second" via `globalBeatIndex` (2 beats ≈ 1 s at 120 BPM fallback) so
// the cadence is music-locked rather than wall-clock-locked.
//
// Captured per snapshot:
//   alive / stable web counts            — pool cap + cadence verification (Step 1)
//   spawnAccumulator + sinceSpawn beats  — spawn cadence after minSpawnGapBeats raise
//   spider(acc, blend, cooldown)         — trigger gate health (Step 6)
//   strandLuma / dropLuma / drop÷strand  — numeric proxy for the silk-vs-drop ratio
//                                          shift (~2.0 in v4 → ~3.0 after Step 5)
//
// The luminance values are intentional proxies, not GPU read-backs. The v4→v5
// ratio shift is large enough that a Swift-side proxy is sufficient to verify
// the change landed; an exact texture sample would be 10× the code for no
// added confidence.

import Foundation
import os.log
import Shared

#if DEBUG && ARACHNE_M7_DIAG
private let m7DiagLogger = Logger(subsystem: "com.phosphene.presets", category: "ArachneM7Diag")

extension ArachneState {

    /// Emit one ARACHNE_M7_DIAG line if the per-second bucket has advanced.
    /// Called from `_tick` while the lock is held.
    func m7DiagSnapshot(features: FeatureVector) {
        let secondBucket = Int(globalBeatIndex / 2.0)
        guard secondBucket != lastM7DiagBucket else { return }
        lastM7DiagBucket = secondBucket

        var aliveCount = 0
        var stableCount = 0
        for web in webs where web.isAlive != 0 {
            aliveCount += 1
            if WebStage(rawValue: web.stage) == .stable { stableCount += 1 }
        }
        let beatsSinceSpawn = globalBeatIndex - lastSpawnBeatIndex

        // Numeric proxies (v4 baseline). Step 5 (drops-as-hero) will modulate
        // dropEmissionGain by audio and reduce silk tint — the ratio shifts
        // from ~2.0 (v4: silk dominates) to ~3.0 (v5: drops dominate).
        let baseEmissionGain = 1.0 + 0.18 * features.bassAttRel
        let expectedStrandLuma = baseEmissionGain * 0.50  // v4: silkTint × 0.50
        let expectedDropLuma: Float = 1.0                 // v4: drops not gain-modulated
        let dropOverStrand = expectedDropLuma / max(expectedStrandLuma, 1e-4)
        let cooldown = max(0, Self.sessionCooldownDuration - timeSinceLastSpider)

        m7DiagLogger.debug("""
            ARACHNE_M7_DIAG \
            alive=\(aliveCount) stable=\(stableCount) \
            spawnAcc=\(self.spawnAccumulator, format: .fixed(precision: 2)) \
            sinceSpawn=\(beatsSinceSpawn, format: .fixed(precision: 1))b \
            spider(acc=\(self.sustainedSubBassAccumulator, format: .fixed(precision: 2)) \
            blend=\(self.spiderBlend, format: .fixed(precision: 2)) \
            cd=\(cooldown, format: .fixed(precision: 0))s) \
            strandLuma=\(expectedStrandLuma, format: .fixed(precision: 3)) \
            dropLuma=\(expectedDropLuma, format: .fixed(precision: 3)) \
            drop/strand=\(dropOverStrand, format: .fixed(precision: 2))
            """)
    }
}
#endif
