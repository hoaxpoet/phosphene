// WitchlightHeadFramingTests — is the burning head actually on screen?
//
// WL.7 §1. Every music coupling Witchlight has is most visible AT THE HEAD: the flare
// fires there, the newest beads are brightest there, and both the WL.4 breath and the
// WL.5 energy gate show most strongly there. Matt's sixth M7 was "the ribbon is moving
// faster than the camera can catch up, leaving the front of the ribbon out of frame for
// much of the run" — if that is true, the coupling is real and INVISIBLE, and no ninth
// route fixes it.
//
// Measured on the CPU by replicating `wl_project` from Witchlight.metal exactly (the
// four lines below the `// mirror of wl_project` marker). No GPU, no PNGs: the question
// is a coordinate question, and the projection is eight lines of arithmetic.
//
// Driven by the committed real-music fixtures (FA #27), same as every other Witchlight
// harness.

import Foundation
import Testing
@testable import Renderer
@testable import Shared

// MARK: - Projection mirror

private enum WLProject {

    /// Mirror of `wl_tumble` / `wl_project` in `Sources/Renderer/Shaders/Witchlight.metal`.
    /// If that projection changes, this changes with it — a drifted mirror would report
    /// framing that the GPU is not drawing.
    static func ndc(_ path: WitchlightPath, x: Float, y: Float, aspect: Float,
                    camX: Float, camY: Float) -> SIMD2<Float> {
        let px = x - camX, py = y - camY
        let cy = cos(path.tumbleYaw),   sy = sin(path.tumbleYaw)
        let cp = cos(path.tumblePitch), sp = sin(path.tumblePitch)
        let cr = cos(path.tumbleRoll),  sr = sin(path.tumbleRoll)
        let a = SIMD3<Float>(px * cr - py * sr, px * sr + py * cr, 0)
        let b = SIMD3<Float>(a.x, a.y * cp, a.y * sp)
        let rel = SIMD3<Float>(b.x * cy + b.z * sy, b.y, -b.x * sy + b.z * cy)
        let camDist: Float = 3.0
        let persp = camDist / max(camDist - rel.z * path.viewScale, 0.35)
        var ndc = SIMD2<Float>(rel.x, rel.y) * path.viewScale * persp
        ndc.x /= max(aspect, 0.05)
        return ndc
    }
}

// MARK: - Tests

@Suite("Witchlight head framing (WL.7)")
struct WitchlightHeadFramingTests {

    private static let aspect: Float = 16.0 / 9.0

    private struct Report {
        var frames = 0
        var headOffFrame = 0
        var headOutsideInset = 0
        var beadsSeen = 0
        var beadsOffFrame = 0
        var worstHead: Float = 0
    }

    /// The head is the newest bead — the burning tip, where the flare and the breath show.
    /// `inset` 0.9 catches a head that is technically on screen but pinned to the bezel,
    /// which reads the same to a viewer as absent.
    private func measure(_ track: String) throws -> Report {
        let drive = try WitchlightFixtureDrive.load(track, aspect: Self.aspect)
        let path = WitchlightPath()
        var report = Report()
        var structure = StructuralPrediction()
        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
            guard let head = path.beads.last else { continue }
            report.frames += 1
            let ndc = WLProject.ndc(path, x: head.posX, y: head.posY, aspect: Self.aspect,
                                    camX: path.cameraX, camY: path.cameraY)
            let reach = max(abs(ndc.x), abs(ndc.y))
            report.worstHead = max(report.worstHead, reach)
            if reach > 1.0 { report.headOffFrame += 1 }
            if reach > 0.9 { report.headOutsideInset += 1 }
            for bead in path.beads {
                let p = WLProject.ndc(path, x: bead.posX, y: bead.posY, aspect: Self.aspect,
                                      camX: path.cameraX, camY: path.cameraY)
                report.beadsSeen += 1
                if max(abs(p.x), abs(p.y)) > 1.0 { report.beadsOffFrame += 1 }
            }
        }
        return report
    }

    @Test("head-off-frame fraction, per fixture", arguments: WitchlightFixtureDrive.tracks)
    func headStaysInFrame(track: String) throws {
        let r = try measure(track)
        let pct = { (n: Int, d: Int) in d > 0 ? 100 * Double(n) / Double(d) : 0 }
        print("""
              WL.7 framing [\(track)]  frames \(r.frames)
                head off-frame      \(String(format: "%.1f", pct(r.headOffFrame, r.frames))) %
                head outside 0.9    \(String(format: "%.1f", pct(r.headOutsideInset, r.frames))) %
                worst head reach    \(String(format: "%.2f", r.worstHead)) (1.0 = frame edge)
                beads off-frame     \(String(format: "%.1f", pct(r.beadsOffFrame, r.beadsSeen))) %
              """)
        #expect(r.frames > 100, "fixture produced no beads — check the drive")
        #expect(pct(r.headOffFrame, r.frames) <= 2.0, """
            the burning head is off frame on \(String(format: "%.1f", pct(r.headOffFrame, r.frames)))% \
            of frames. That is where every music coupling this preset has actually shows — the \
            flare, the newest and brightest beads, the WL.4 breath, the WL.5 energy gate. A head \
            off frame makes the coupling real and INVISIBLE, which is the whole of Matt's \
            "still not tied to the music" (six M7 rounds). Before WL.7 this read 33 / 35 / 45 %.

            Fix the CAMERA (`reframe`), not this number. And do NOT fix it by fitting more into \
            frame — that shrinks the drawing and the WL.2-j distinctness gate will (correctly) \
            catch it, as it caught all three WL.6 attempts.
            """)
    }
}
