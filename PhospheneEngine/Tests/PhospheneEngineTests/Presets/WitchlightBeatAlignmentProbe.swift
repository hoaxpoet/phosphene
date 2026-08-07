// WitchlightBeatAlignmentProbe — WL.8 diagnostic, not a gate.
//
// Matt, 2026-08-05, after WL.7 landed: "Ribbon feels connected to the music, though how
// is not obvious." The question this answers is not "is it coupled" (it is, eight routes,
// all gated) but "does anything HAPPEN at the moment a beat lands, where the eye is".
//
// Runs the production path over a real recorded session and reports, for the two things
// that fire in time — the head flare and the downbeat bead promotion — how they sit
// against the session's own beat grid.
//
//   WITCHLIGHT_SESSION=<dir> swift test --package-path PhospheneEngine \
//       --filter WitchlightBeatAlignment

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

@Suite("Witchlight beat alignment probe (WL.8 diagnostic)")
struct WitchlightBeatAlignmentProbe {

    static func medianAbs(_ xs: [Float]) -> Float {
        let a = xs.map { abs($0) }.sorted()
        return a.isEmpty ? 0 : a[a.count / 2]
    }

    /// WL.12 — what the four newly-measurable routes actually produce, on the committed
    /// fixtures. Bands are set FROM this, never the other way round.
    @Test("WL.12 route metrics on the committed fixtures", arguments: WitchlightFixtureDrive.tracks)
    func routeMetrics(track: String) throws {
        let drive = try WitchlightFixtureDrive.load(track)
        let path = WitchlightPath()
        WitchlightFixtureDrive.run(path, over: drive)
        let names = ["beadHueSpread", "promotedShareOfTrail", "pulsesPerMinute",
                     "trailContractionDepth", "headingTurnsPerTrail", "penSpeedSwing",
                     "ribbonBreathSwing"]
        let cells = names.map { n -> String in
            guard let v = path.responseMetric(n) else { return "\(n)=nil" }
            return String(format: "%@=%.3f", n, v)
        }
        print("WL.12 [\(track)] " + cells.joined(separator: "  "))
    }

    @Test("where the flare lands relative to the beat grid")
    func flareVsGrid() throws {
        guard let dir = ProcessInfo.processInfo.environment["WITCHLIGHT_SESSION"] else { return }
        let url = URL(fileURLWithPath: dir)
        let drive = try WitchlightFixtureDrive.load(sessionDirectory: url, name: "session")
        let series = try SessionColumnSeries.load(directory: url)
        // Reference is the GRID, not `beatPhase01`.
        //
        // The first cut of this probe scored flares against `beatPhase01` and it is the wrong
        // signal: on this session it wrapped 24 times in 215 s where 171 BPM demands 614. The
        // live BeatPredictor is effectively stalled on this material, so ANY firing pattern
        // scores near-chance against it and the metric cannot tell a fix from a no-op.
        // Beat times are therefore synthesised from the cached grid — the bar wraps, plus
        // `60 / grid_bpm` steps inside each bar — which is the thing the preset actually locks
        // to. (Both readings happen to agree on the pre-WL.8 trigger: 0.247 vs 0.250.)
        let barPhase = (series.floatSeries("barPhase01_permille") ?? []).map { ($0 ?? 0) * 0.001 }
        let gridBPM = (series.floatSeries("grid_bpm") ?? []).compactMap { $0 }.first { $0 > 1 } ?? 120
        let period = 60.0 / gridBPM
        let beatsPerBar = Int((series.floatSeries("beatsPerBar") ?? []).compactMap { $0 }.first ?? 4)

        // WL.11 — replay the RECORDED drift through the same setter the app tick uses, so the
        // probe measures the compensated firing times rather than an idealised version.
        let driftSeries = (series.floatSeries("drift_ms") ?? []).map { $0 ?? 0 }
        let path = WitchlightPath()
        var structure = StructuralPrediction()
        var flareFrames: [Int] = []
        var lastFlareCount = 0
        var elapsed: [Float] = []
        var clock: Float = 0

        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            if i < driftSeries.count { path.ingestBeatDrift(milliseconds: driftSeries[i]) }
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
            clock += drive.features[i].deltaTime
            elapsed.append(clock)
            if path.flareCount > lastFlareCount { flareFrames.append(i); lastFlareCount = path.flareCount }
        }

        // Grid beat times: each downbeat, plus one period per beat inside the bar.
        var beats: [Float] = []
        for i in 1..<min(barPhase.count, elapsed.count)
        where barPhase[i - 1] > 0.85 && barPhase[i] < 0.15 {
            for k in 0..<max(beatsPerBar, 1) { beats.append(elapsed[i] + Float(k) * period) }
        }
        let downbeats = beats.count / max(beatsPerBar, 1)

        // Distance from each flare to the nearest grid beat, as a fraction of a beat
        // (0 = on it, 0.5 = maximally between two). Uniformly-random firing averages 0.25.
        var offsets: [Float] = []
        for f in flareFrames where f < elapsed.count {
            guard let nearest = beats.min(by: { abs($0 - elapsed[f]) < abs($1 - elapsed[f]) }) else { continue }
            offsets.append(abs(nearest - elapsed[f]) / period)
        }
        let onBeat = offsets.filter { $0 < 0.1 }.count
        let mean = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Float(offsets.count)

        // WL.9 — head framing on the SAME session drive. Matt's 2026-08-06T17-27-21Z report
        // was "the camera cannot keep up with the head because it is moving too fast", which
        // is the WL.7 failure mode returning; the suspect is WL.8's wider speed swing.
        var headOff = 0, framed = 0
        let aspect: Float = 16.0 / 9.0
        let path2 = WitchlightPath()
        var st2 = StructuralPrediction()
        for i in 0..<drive.features.count {
            st2.sectionIndex = drive.sectionIndex[i]
            path2.ingestStructure(st2)
            path2.advance(deltaTime: drive.features[i].deltaTime,
                          features: drive.features[i], stems: drive.stems[i])
            guard let head = path2.beads.last else { continue }
            framed += 1
            let px = head.posX - path2.cameraX, py = head.posY - path2.cameraY
            let cy = cos(path2.tumbleYaw), sy = sin(path2.tumbleYaw)
            let cp = cos(path2.tumblePitch), sp = sin(path2.tumblePitch)
            let cr = cos(path2.tumbleRoll), sr = sin(path2.tumbleRoll)
            let a = SIMD3<Float>(px * cr - py * sr, px * sr + py * cr, 0)
            let b = SIMD3<Float>(a.x, a.y * cp, a.y * sp)
            let rel = SIMD3<Float>(b.x * cy + b.z * sy, b.y, -b.x * sy + b.z * cy)
            let persp = 3.0 / max(3.0 - rel.z * path2.viewScale, 0.35)
            var ndc = SIMD2<Float>(rel.x, rel.y) * path2.viewScale * persp
            ndc.x /= aspect
            if max(abs(ndc.x), abs(ndc.y)) > 1.0 { headOff += 1 }
        }
        let speedSwing = path2.responseMetric("penSpeedSwing") ?? 0

        let seconds = clock
        print("""

              WL.8 beat alignment — session \(url.lastPathComponent)
                duration            \(String(format: "%.0f", seconds)) s, \(drive.features.count) frames
                downbeat bursts     \(path.flareCount)  (\(String(format: "%.2f", Float(path.flareCount) / seconds))/s)
                off-beat pulses     \(path.offBeatCount)  (\(String(format: "%.2f", Float(path.offBeatCount) / seconds))/s)
                combined pulse rate \(String(format: "%.2f", Float(path.flareCount + path.offBeatCount) / seconds))/s
                head flares         \(flareFrames.count)  (\(String(format: "%.2f", Float(flareFrames.count) / seconds))/s)
                  mean |offset|     \(String(format: "%.3f", mean)) beats vs the GRID
                  ^ WL.11: a non-zero value here is now EXPECTED and is the drift correction,
                    not an error. The pulse deliberately leads or lags the grid by the
                    tracker's own estimate of how far the grid sits from the audible beat.
                    0.25 still means "no relationship at all"; ~0 means compensation is off.
                  within 10 % of a beat  \(String(format: "%.0f", 100 * Float(onBeat) / Float(max(offsets.count, 1)))) %  (20 % = chance)
                downbeats in grid   \(downbeats)
                beads promoted      \(path.promotionCount)
                beads alive at end  \(path.beads.count)
                turns / sections    \(path.turnCount) / \(path.sectionEventCount)
                head OFF FRAME      \(String(format: "%.1f", 100 * Double(headOff) / Double(max(framed, 1)))) %  (WL.7 gate: <= 2 %)
                pen speed swing     \(String(format: "%.2f", speedSwing))x
                drift comp applied  \(String(format: "%+.1f", path.beatDriftSeconds * 1000)) ms at end \
                (recorded |drift| p50 \(String(format: "%.0f", Self.medianAbs(driftSeries))) ms)

              """)
    }
}
