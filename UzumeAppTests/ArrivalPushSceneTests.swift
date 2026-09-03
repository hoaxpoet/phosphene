// ArrivalPushSceneTests — the camera push is flash-safe, and its whiteout genuinely
// converges. (DS.5)
//
// Same idiom as PreparationApertureTests / MitosisSketchRenderTests §Criterion 4 (D-157):
// step the scene frame by frame, measure mean luminance, require the per-frame step to
// stay tiny even though this scene's whole point is a large brightness change — the D-157
// gate is about the *rate*, not the destination.

import AppKit
import Session
import Shared
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Rendering helpers

@MainActor
private func renderScene(_ scene: ArrivalPushScene, size: CGSize) -> NSBitmapImageRep? {
    renderCanvas(size: size) { context, size in scene.draw(in: &context, size: size) }
}

@MainActor
private func renderScene(_ scene: ApertureScene, size: CGSize) -> NSBitmapImageRep? {
    renderCanvas(size: size) { context, size in scene.draw(in: &context, size: size) }
}

@MainActor
private func renderCanvas(
    size: CGSize, _ draw: @escaping (inout GraphicsContext, CGSize) -> Void
) -> NSBitmapImageRep? {
    let canvas = Canvas { context, size in draw(&context, size) }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
    let renderer = ImageRenderer(content: canvas)
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

private func lumaMean(_ rep: NSBitmapImageRep) -> Double {
    guard let data = rep.bitmapData else { return 0 }
    let width = rep.pixelsWide, height = rep.pixelsHigh, spp = rep.samplesPerPixel, row = rep.bytesPerRow
    var sum = 0.0
    for y in 0..<height {
        let base = y * row
        for x in 0..<width {
            let px = base + x * spp
            sum += 0.2126 * Double(data[px]) + 0.7152 * Double(data[px + 1]) + 0.0722 * Double(data[px + 2])
        }
    }
    return sum / Double(width * height) / 255
}

private func heardProfiles(_ count: Int) -> [TrackProfile] {
    (0..<count).map { i in
        var balance = StemFeatures.zero
        balance.drumsEnergy = 0.3 + 0.4 * Float(i % 3) / 2
        balance.vocalsEnergy = 0.2 + 0.3 * Float((i + 1) % 2)
        balance.bassEnergy = 0.4
        balance.otherEnergy = 0.3
        let mood = EmotionalState(valence: Float(i % 4) / 2 - 0.75, arousal: Float((i * 3) % 5) / 2 - 1)
        return TrackProfile(
            bpm: 90 + Float(i * 7 % 50),
            key: "A minor",
            mood: mood,
            spectralCentroidAvg: 0.3 + 0.4 * Float(i % 5) / 4,
            stemEnergyBalance: balance,
            beatIrregular: i % 6 == 0
        )
    }
}

// MARK: - Suite

@Suite("ArrivalPushScene")
@MainActor
struct ArrivalPushSceneTests {

    @Test("nothing before it starts: progress 0 matches the resting, fully-open aperture")
    func atRest_matchesApertureAlone() throws {
        let size = CGSize(width: 288, height: 180)
        let character = PreparationCharacter(profiles: heardProfiles(20))
        let push = ArrivalPushScene(character: character, time: 12, progress: 0)
        let aperture = ApertureScene(openness: 1, character: character, time: 12)
        let pushRep = try #require(renderScene(push, size: size))
        let apertureRep = try #require(renderScene(aperture, size: size))
        #expect(abs(lumaMean(pushRep) - lumaMean(apertureRep)) < 0.01, "progress 0 should draw nothing extra")
    }

    @Test("the whiteout genuinely converges: progress 1 is bright, uniform light")
    func atEnd_isWhiteout() throws {
        let size = CGSize(width: 288, height: 180)
        let character = PreparationCharacter(profiles: heardProfiles(20))
        let push = ArrivalPushScene(character: character, time: 12, progress: 1)
        let rep = try #require(renderScene(push, size: size))
        #expect(lumaMean(rep) > 0.85, "progress 1 should read as filled with light: luma \(lumaMean(rep))")
    }

    /// A full push-and-hold, stepped at 20 fps (coarser than the 30 fps the view draws
    /// at, so the measured delta bounds the real one from above — same choice
    /// PreparationApertureTests makes for the same reason).
    @Test("luminance changes gradually across the whole push — no strobe (D-157)")
    func flashSafe_acrossFullPush() async throws {
        let size = CGSize(width: 288, height: 180)
        let character = PreparationCharacter(profiles: heardProfiles(20))
        let fps = 20.0, pushDuration = 2.7, holdDuration = 0.52
        let frameCount = Int((pushDuration + holdDuration) * fps)

        var prev: Double?
        var maxDelta = 0.0, maxDeltaAt = 0.0, lo = 1.0, hi = 0.0
        for frame in 0..<frameCount {
            let elapsed = Double(frame) / fps
            let progress = min(1, elapsed / pushDuration)
            let scene = ArrivalPushScene(character: character, time: elapsed, progress: progress)
            let rep = try #require(renderScene(scene, size: size))
            let mean = lumaMean(rep)
            if let previous = prev {
                let delta = abs(mean - previous)
                if delta > maxDelta { maxDelta = delta; maxDeltaAt = elapsed }
            }
            lo = min(lo, mean); hi = max(hi, mean); prev = mean
            if frame % 8 == 0 { await Task.yield() }
        }
        let report = String(
            format: "[ARRIVAL] flash: maxΔ/frame %.4f (at %.2f s)  luma range %.3f–%.3f  frames %d @ %.0f fps",
            maxDelta,
            maxDeltaAt,
            lo,
            hi,
            frameCount,
            fps
        )
        print(report)
        #expect(maxDelta < 0.05, "brightness must change gradually, never strobe: maxΔ \(maxDelta)")
    }
}
