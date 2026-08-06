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
                let w = Int(clock / 10)
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
            print("WL.9b speed sweep — \(url.lastPathComponent)\n" + lines.joined(separator: "\n"))
        }
    }
}
