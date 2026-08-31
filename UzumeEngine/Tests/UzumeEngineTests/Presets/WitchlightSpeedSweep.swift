// WitchlightSpeedSweep — the pen-speed lever, measured on REAL sessions through the real path.
//
// WL.9b. Matt, session `2026-08-06T17-27-21Z`: "The ribbon builds too fast and not in sync
// with the actual beat and downbeat. In addition, the camera cannot keep up with the head of
// the ribbon because it is moving too fast."
//
// Both trace to one constant. WL.8 took `arousalSpreadDivisor` 2.0 → 1.5 to answer "the speed
// route feels weak", and validated it with a Python model of the arousal EMA alone — which
// omitted `energyGateForSpeed`, a 0.25…1.75 multiplier sitting on the SAME product. The model
// said 1.42x → 1.57x. The real path on his 171 BPM session says **9.95x**.
//
// This harness exists so that mistake cannot repeat: it drives the production `WitchlightPath`
// over whole recorded sessions and reports the realised swing AND the framing consequence
// (head-off-frame is what "the camera cannot keep up" means numerically), because the two are
// coupled — a faster pen grows the trail, the auto-fit zooms out, and the head runs for the edge.
//
//   WITCHLIGHT_SESSIONS=<dirA>:<dirB> swift test --package-path PhospheneEngine \
//       --filter WitchlightSpeedSweep

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

@Suite("Witchlight pen-speed sweep (WL.9b)")
struct WitchlightSpeedSweep {

    private static let aspect: Float = 16.0 / 9.0

    private struct Result {
        var swing: Double
        var headOffPercent: Double
        var beadsAtEnd: Int
    }

    /// Gate defaults track PRODUCTION, not the pre-WL.9b values — a sweep whose "baseline"
    /// row silently uses retired constants reports swings nobody ships.
    private func run(_ drive: WitchlightFixtureDrive.Drive, divisor: Float,
                     gateFloor: Float = WitchlightTuning().energyGateFloor,
                     gateSpan: Float = WitchlightTuning().energyGateSpan) -> Result {
        var tuning = WitchlightTuning()
        tuning.arousalSpreadDivisor = divisor
        tuning.energyGateFloor = gateFloor
        tuning.energyGateSpan = gateSpan
        tuning.energyGateCap = gateFloor + gateSpan
        let path = WitchlightPath()
        path.overrideTuning(tuning)
        var structure = StructuralPrediction()
        var off = 0, framed = 0
        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
            guard let head = path.beads.last else { continue }
            framed += 1
            if Self.headReach(path, head) > 1.0 { off += 1 }
        }
        return Result(swing: path.responseMetric("penSpeedSwing") ?? 0,
                      headOffPercent: 100 * Double(off) / Double(max(framed, 1)),
                      beadsAtEnd: path.beads.count)
    }

    /// Mirror of `wl_project`, reduced to the one number that matters here.
    private static func headReach(_ path: WitchlightPath, _ head: WitchlightBead) -> Float {
        let px = head.posX - path.cameraX, py = head.posY - path.cameraY
        let cy = cos(path.tumbleYaw), sy = sin(path.tumbleYaw)
        let cp = cos(path.tumblePitch), sp = sin(path.tumblePitch)
        let cr = cos(path.tumbleRoll), sr = sin(path.tumbleRoll)
        let a = SIMD3<Float>(px * cr - py * sr, px * sr + py * cr, 0)
        let b = SIMD3<Float>(a.x, a.y * cp, a.y * sp)
        let rel = SIMD3<Float>(b.x * cy + b.z * sy, b.y, -b.x * sy + b.z * cy)
        let persp = 3.0 / max(3.0 - rel.z * path.viewScale, 0.35)
        var ndc = SIMD2<Float>(rel.x, rel.y) * path.viewScale * persp
        ndc.x /= aspect
        return max(abs(ndc.x), abs(ndc.y))
    }

    /// WL.10 — does the framed scale ever come back UP?
    ///
    /// Matt, 2026-08-06: "Does the camera ever zoom back in when the ribbon is back to making
    /// tighter shapes and forms?" `viewScale` rising = zooming IN, so the question is whether
    /// the series recovers after a wide passage or only ratchets outward.
    ///
    /// Two figures, because either alone can mislead. **Span** (p90/p10) says how much total
    /// range the framing uses — a big span with no recovery is just a long slide outward.
    /// **Recovery events** counts the times the scale actually climbs ≥ 20 % inside a 15 s
    /// span, which is the thing a viewer would notice as "it came back in".
    ///
    /// NOT "fraction of frames rising": that measures time-in-transit, so making the zoom-in
    /// FASTER lowers it. It read 19.6 % → 12.9 % across a shrink-τ sweep that changed the
    /// actual framing not at all, and briefly suggested a fix was a regression.
    static func recoveryReport(_ scales: [Float], clockPerFrame: [FeatureVector]) -> [String] {
        guard scales.count > 60 else { return ["  recovery: too few frames"] }
        let sorted = scales.sorted()
        let p10 = sorted[sorted.count / 10], p90 = sorted[9 * sorted.count / 10]

        // Walk a 15 s window; count a recovery each time the scale climbs >= 20 % from the
        // window's running minimum, then re-arm on a fresh minimum.
        var events = 0
        var windowMin = scales[0]
        var elapsed: Float = 0
        var sinceReset: Float = 0
        for (i, v) in scales.enumerated() {
            let dt = i < clockPerFrame.count ? max(clockPerFrame[i].deltaTime, 1.0 / 240) : 1.0 / 60
            elapsed += dt; sinceReset += dt
            if v < windowMin { windowMin = v; sinceReset = 0 }
            if v > windowMin * 1.20 { events += 1; windowMin = v; sinceReset = 0 }
            if sinceReset > 15 { windowMin = v; sinceReset = 0 }
        }
        return [String(format: "  RECOVERY: span p90/p10 %.2fx (p10 %.2f, p90 %.2f) | zoom-in events %d over %.0f s",
                       p90 / max(p10, 0.01), p10, p90, events, elapsed)]
    }

    @Test("realised speed swing and head framing vs the arousal divisor")
    func sweep() throws {
        guard let joined = ProcessInfo.processInfo.environment["WITCHLIGHT_SESSIONS"] else { return }
        let divisors: [Float] = [1.5, 2.0, 2.5, 3.0, 4.0]
        for dir in joined.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: dir)
            let drive = try WitchlightFixtureDrive.load(sessionDirectory: url, name: "s")
            var lines: [String] = []
            for d in divisors {
                let r = run(drive, divisor: d)
                lines.append(String(format: "  divisor %.1f | swing %6.2fx | head off frame %5.1f %% | beads %3d",
                                    d, r.swing, r.headOffPercent, r.beadsAtEnd))
            }
            // WL.10 — the fit window: how much of the recent past the scale is fitted over.
            for w in [Float(0), 20, 15, 12, 8] {
                var t = WitchlightTuning()
                t.fitWindowSeconds = w
                let pp = WitchlightPath()
                pp.overrideTuning(t)
                var stt = StructuralPrediction()
                var sc: [Float] = []
                var off = 0, seen = 0
                for i in 0..<drive.features.count {
                    stt.sectionIndex = drive.sectionIndex[i]
                    pp.ingestStructure(stt)
                    pp.advance(deltaTime: drive.features[i].deltaTime,
                               features: drive.features[i], stems: drive.stems[i])
                    sc.append(pp.viewScale)
                    if let h = pp.beads.last { seen += 1; if Self.headReach(pp, h) > 1.0 { off += 1 } }
                }
                let sorted = sc.sorted()
                let p10 = sorted[sorted.count / 10], p90 = sorted[9 * sorted.count / 10]
                var events = 0; var wmin = sc[0]; var since: Float = 0
                for (i, v) in sc.enumerated() {
                    since += i < drive.features.count ? max(drive.features[i].deltaTime, 1.0 / 240) : 1.0 / 60
                    if v < wmin { wmin = v; since = 0 }
                    if v > wmin * 1.20 { events += 1; wmin = v; since = 0 }
                    if since > 15 { wmin = v; since = 0 }
                }
                // PUMPING probe: the largest per-frame fractional change in the framed scale.
                // A pump on a section contraction shows up here and in no still frame.
                // Skip the first 5 s: `rmsRadius` starts at a 0.4 seed and snaps to the real
                // figure on the first frames, which is a one-off, not a pump. Measuring it as
                // one reports ~55 % identically at EVERY window including the baseline, i.e.
                // it says nothing about the change.
                let skip = min(300, sc.count / 4)
                let steady = Array(sc.dropFirst(skip))
                let maxStep = zip(steady, steady.dropFirst()).map { abs($1 - $0) / max($0, 0.01) }.max() ?? 0
                lines.append(String(format: "  fitWindow %2.0fs | span %.2fx (p10 %.2f p90 %.2f) | zoom-ins %2d | head off %4.1f %% | maxΔ/frame %.3f %%",
                                    w, p90 / max(p10, 0.01), p10, p90, events,
                                    100 * Double(off) / Double(max(seen, 1)), maxStep * 100))
            }

            // The energy gate is the dominant term; sweep it at the shipped divisor.
            for (lo, span) in [(Float(0.25), Float(1.5)), (0.55, 0.9), (0.70, 0.6), (0.85, 0.3)] {
                let r = run(drive, divisor: 2.0, gateFloor: lo, gateSpan: span)
                lines.append(String(format: "  gate %.2f…%.2f | swing %6.2fx | head off frame %5.1f %% | beads %3d",
                                    lo, lo + span, r.swing, r.headOffPercent, r.beadsAtEnd))
            }
            // WHEN does the head leave frame? Bursty => the follow lags a manoeuvre;
            // spread evenly => the fit itself is wrong on long material.
            // PRODUCTION DEFAULTS, deliberately — a temporal claim validated under a swept
            // configuration is the WL.9b mistake repeated (the partial-model swing number).
            let path = WitchlightPath()
            var st2 = StructuralPrediction()
            var offByWindow: [Int: (Int, Int)] = [:]
            var scaleByWindow: [Int: [Float]] = [:]
            var scales: [Float] = []
            var clock: Float = 0
            var worst: Float = 0
            for i in 0..<drive.features.count {
                st2.sectionIndex = drive.sectionIndex[i]
                path.ingestStructure(st2)
                path.advance(deltaTime: drive.features[i].deltaTime,
                             features: drive.features[i], stems: drive.stems[i])
                clock += drive.features[i].deltaTime
                guard let head = path.beads.last else { continue }
                let reach = Self.headReach(path, head)
                worst = max(worst, reach)
                scales.append(path.viewScale)
                let w = Int(clock / 10)
                scaleByWindow[w, default: []].append(path.viewScale)
                var e = offByWindow[w] ?? (0, 0)
                e.1 += 1
                if reach > 1.0 { e.0 += 1 }
                offByWindow[w] = e
            }
            let windows = offByWindow.keys.sorted().map { k -> String in
                let (o, n) = offByWindow[k]!
                return String(format: "%2.0f", 100 * Double(o) / Double(max(n, 1)))
            }
            lines.append("  off-frame % by 10 s window: " + windows.joined(separator: " "))
            lines.append(String(format: "  worst head reach %.2f (1.0 = edge)", worst))
            lines.append(contentsOf: Self.recoveryReport(scales, clockPerFrame: drive.features))
            lines.append("  viewScale by 10 s window: " + scaleByWindow.keys.sorted().map {
                String(format: "%.2f", scaleByWindow[$0]!.reduce(0, +) / Float(scaleByWindow[$0]!.count))
            }.joined(separator: " "))
            print("WL.9b speed sweep — \(url.lastPathComponent)\n" + lines.joined(separator: "\n"))
        }
    }
}
