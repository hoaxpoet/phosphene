// PreparationApertureTests — the cave is a pure function of readiness, renders under
// reduced motion, and is flash-safe across a full preparation. (DS.4 tasks 5, 8, 9)
//
// The flash test follows MitosisSketchRenderTests §Criterion 4 (D-157): step the
// scene frame by frame, measure mean luminance, and require the per-frame step to
// stay tiny. A number here that cannot be defended is a stop-and-report, not a
// tuning target.
//
//   TEST_RUNNER_UZUME_APERTURE_FRAMES=1  also writes sample frames to
//   docs/reviews/DS.4/frames/ for the M7 page.

import AppKit
import Session
import Shared
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Rendering helpers

@MainActor
private func renderScene(_ scene: ApertureScene, size: CGSize) -> NSBitmapImageRep? {
    let canvas = Canvas { context, size in
        var scene = scene
        scene.draw(in: &context, size: size)
    }
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let renderer = ImageRenderer(content: canvas)
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

/// Mean Rec. 709 luma over the frame, 0…1.
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

private func brightestPixel(_ rep: NSBitmapImageRep) -> Double {
    guard let data = rep.bitmapData else { return 0 }
    let width = rep.pixelsWide, height = rep.pixelsHigh, spp = rep.samplesPerPixel, row = rep.bytesPerRow
    var peak = 0.0
    for y in 0..<height {
        for x in 0..<width {
            let px = y * row + x * spp
            let luma = 0.2126 * Double(data[px]) + 0.7152 * Double(data[px + 1]) + 0.0722 * Double(data[px + 2])
            peak = max(peak, luma)
        }
    }
    return peak / 255
}

private func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url)
}

private func projectRoot(file: StaticString = #filePath) -> URL {
    var url = URL(fileURLWithPath: "\(file)")
    for _ in 0..<10 {
        url = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path) { return url }
    }
    return url
}

private var dumpFrames: Bool { ProcessInfo.processInfo.environment["UZUME_APERTURE_FRAMES"] == "1" }

/// A varied playlist, so the character has something to work with.
private func heardProfiles(_ count: Int) -> [TrackProfile] {
    (0..<count).map { i in
        var balance = StemFeatures.zero
        balance.drumsEnergy = 0.3 + 0.4 * Float(i % 3) / 2
        balance.vocalsEnergy = 0.2 + 0.3 * Float((i + 1) % 2)
        balance.bassEnergy = 0.4
        balance.otherEnergy = 0.3
        return TrackProfile(
            bpm: 90 + Float(i * 7 % 50),
            key: "A minor",
            mood: EmotionalState(valence: Float(i % 4) / 2 - 0.75, arousal: Float((i * 3) % 5) / 2 - 1),
            spectralCentroidAvg: 0.3 + 0.4 * Float(i % 5) / 4,
            stemEnergyBalance: balance,
            beatIrregular: i % 6 == 0
        )
    }
}

// MARK: - Suite

@Suite("PreparationAperture")
@MainActor
struct PreparationApertureTests {

    // MARK: Task 5 — the aperture is a pure function of readiness

    @Test("shut until the first track is heard; open at the four stops; monotonic within each")
    func apertureStop_isPureAndOrdered() {
        #expect(ApertureStop.openness(level: .preparing, heard: 0, total: 40) == 0)
        #expect(ApertureStop.openness(level: .readyForFirstTracks, heard: 0, total: 40) == 0)
        #expect(ApertureStop.openness(level: .reactiveFallback, heard: 5, total: 40) == 0)
        let pinprick = ApertureStop.openness(level: .preparing, heard: 1, total: 40)
        #expect(pinprick == ApertureStop.pinprick)
        let three = ApertureStop.openness(level: .readyForFirstTracks, heard: 3, total: 40)
        let twenty = ApertureStop.openness(level: .partiallyPlanned, heard: 20, total: 40)
        let done = ApertureStop.openness(level: .fullyPrepared, heard: 40, total: 40)
        #expect(pinprick < three && three < twenty && twenty < done && done == 1)
        // Eight tracks and forty are the same object: same stop, same opening.
        #expect(ApertureStop.openness(level: .readyForFirstTracks, heard: 3, total: 8)
                == ApertureStop.openness(level: .readyForFirstTracks, heard: 3, total: 40))
        // Within a stop, hearing more never closes the cave.
        var last = three
        for heard in 3...19 {
            let now = ApertureStop.openness(level: .readyForFirstTracks, heard: heard, total: 40)
            #expect(now >= last); last = now
        }
    }

    @Test("the playlist changes behaviour, and only from what has been heard")
    func character_derivesFromHeardProfiles() {
        let none = PreparationCharacter()
        let some = PreparationCharacter(profiles: heardProfiles(6))
        #expect(none.heard == 0 && none.depth == 0)
        #expect(some.heard == 6 && some.depth > 0.5)
        #expect(some.moodSpread > 0.2, "a varied playlist churns")
        let uniform = PreparationCharacter(profiles: Array(repeating: heardProfiles(1)[0], count: 6))
        #expect(uniform.moodSpread < 0.001, "a uniform playlist drifts")
        #expect(some.beat > 0 && some.wash > 0 && some.beat + some.wash < 1, "shares of the stem total")
        #expect(some.jitter > 0, "one irregular track in six makes the mouth waver a little")
    }

    // MARK: Task 5/9 — nothing spills while shut; a wide cave is bright

    @Test("nothing spills while shut")
    func shut_isGenuinelyDark() throws {
        let size = CGSize(width: 320, height: 200)
        let scene = ApertureScene(openness: 0, character: PreparationCharacter(), time: 3)
        let shut = try #require(renderScene(scene, size: size))
        // Canvas token luma is ~0.045 (#0B0C10); the rock lift around the mouth adds a little.
        #expect(lumaMean(shut) < 0.08, "shut cave luma \(lumaMean(shut))")
        #expect(brightestPixel(shut) < 0.15, "no ivory, no spectrum while shut: peak \(brightestPixel(shut))")
    }

    // MARK: Task 8 — reduced motion still renders a non-empty aperture

    @Test("under reduced motion the cave renders and widens with readiness")
    func reducedMotion_rendersNonEmptyAperture() throws {
        // Reduced motion pauses the timeline and snaps openness to its target: the
        // frame is exactly the scene at the stop, at whatever time the timeline froze.
        let size = CGSize(width: 320, height: 200)
        let character = PreparationCharacter(profiles: heardProfiles(3))
        let pinprick = try #require(renderScene(
            ApertureScene(openness: ApertureStop.pinprick, character: character, time: 0), size: size))
        let threeOpen = ApertureStop.openness(level: .readyForFirstTracks, heard: 3, total: 8)
        let three = try #require(renderScene(
            ApertureScene(openness: threeOpen, character: character, time: 0), size: size))
        #expect(brightestPixel(pinprick) > 0.6, "the pinprick is a bright point")
        #expect(lumaMean(three) > lumaMean(pinprick) + 0.02, "three-ready is visibly wider than the pinprick")
        #expect(abs(ApertureMotion.eased(from: 0.1, to: 0.42, elapsed: 0) - 0.1) < 1e-9)
        #expect(abs(ApertureMotion.eased(from: 0.1, to: 0.42, elapsed: 30) - 0.42) < 0.001)
    }

    // MARK: Task 9 — flash-safe (D-157)

    /// A full preparation, time-compressed, stepped at 30 fps: forty tracks landing
    /// (including a burst of four in one second), every stop transition, and the
    /// surge on each landing. Reports maxΔ/frame and the luma range; asserts the
    /// Mitosis gate (< 0.05 per frame).
    @Test("luminance changes gradually across a full preparation — no strobe (D-157)")
    func flashSafe_acrossFullPreparation() async throws {
        // 20 fps is the conservative choice: coarser steps than the 30 fps the view
        // draws at, so a per-frame delta here bounds the real one from above.
        let size = CGSize(width: 288, height: 180)
        let fps = 20.0, total = 40
        // Landing schedule (seconds): steady every 3 s, a burst of four at 60 s, three fails.
        var landings: [Double] = []
        var clock = 6.0
        for i in 0..<total {
            landings.append(clock)
            clock += (i >= 20 && i < 24) ? 0.25 : 3.0
        }
        let seconds = (landings.last ?? 0) + 8
        let profiles = heardProfiles(total)
        let framesDir = projectRoot().appendingPathComponent("docs/reviews/DS.4/frames")

        var prev: Double?
        var maxDelta = 0.0, lo = 1.0, hi = 0.0, maxDeltaAt = 0.0
        var easeFrom = 0.0, easeStart = -1e9, surgeStart = -1e9, lastTarget = 0.0
        let frameCount = Int(seconds * fps)
        for frame in 0..<frameCount {
            let now = Double(frame) / fps
            let heard = landings.filter { $0 <= now }.count
            let level: ProgressiveReadinessLevel = heard == 0 ? .preparing
                : heard < 3 ? .preparing
                : heard < total / 2 ? .readyForFirstTracks
                : heard < total ? .partiallyPlanned : .fullyPrepared
            let target = ApertureStop.openness(level: level, heard: heard, total: total)
            if target != lastTarget {
                easeFrom = ApertureMotion.eased(from: easeFrom, to: lastTarget, elapsed: now - easeStart)
                easeStart = now; lastTarget = target
            }
            if heard > 0, landings[heard - 1] > now - 1 / fps { surgeStart = now }
            var scene = ApertureScene(
                openness: ApertureMotion.eased(from: easeFrom, to: target, elapsed: now - easeStart),
                character: PreparationCharacter(profiles: Array(profiles.prefix(heard))),
                time: now
            )
            scene.surge = ApertureMotion.surge(elapsed: now - surgeStart)
            let rep = try #require(renderScene(scene, size: size))
            let mean = lumaMean(rep)
            if let previous = prev {
                let delta = abs(mean - previous)
                if delta > maxDelta { maxDelta = delta; maxDeltaAt = now }
            }
            lo = min(lo, mean); hi = max(hi, mean); prev = mean
            // Yield so parallel main-actor suites are not starved by this loop.
            if frame % 8 == 0 { await Task.yield() }
            if dumpFrames, frame % Int(fps * 6) == 0 {
                try writePNG(rep, to: framesDir.appendingPathComponent(String(format: "f_%03ds.png", Int(now))))
            }
        }
        let report = String(
            format: "[APERTURE] flash: maxΔ/frame %.4f (at %.1f s)  luma range %.3f–%.3f  frames %d @ %.0f fps",
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
