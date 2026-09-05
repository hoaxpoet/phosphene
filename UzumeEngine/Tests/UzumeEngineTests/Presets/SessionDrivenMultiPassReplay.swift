// SessionDrivenMultiPassReplay — PR.10: replay a RECORDED session through
// `MultiPassRenderHarness`, which already reaches every paradigm.
//
// WHY THIS IS SMALL. PR.1 reported that 23 of the 26 presets Matt flagged "cannot be
// replayed from a real session", because `SessionReplayHarness` drives
// `RayMarchPipeline.render` and its coverage gate was scoped to `.rayMarch`. That was
// true of THAT harness and wrong about the codebase: `MultiPassRenderHarness.render`
// already dispatches Dragon Bloom, Skein, Witchlight, Ricercar, Filigree, Meniscus,
// Stave, Mitosis, Cytokinesis, Nacre, Glaze, Floret, Fata Morgana, Fractal Tree, Lumen
// Mosaic, Volumetric Lithograph, Cymatic Resonance and the four `direct` presets down
// their real render paths. The only thing missing was real INPUT.
//
// So this file is the join: `SessionReplayHarness`'s CSV loaders (which PR.10 widened
// from 27 to 46 carried primitives) feeding `MultiPassRenderHarness`'s dispatch. Both
// halves already existed and neither knew about the other.
//
// Usage:
//   REPLAY_SESSION=~/Documents/uzume_sessions/<dir> \
//   REPLAY_PRESET="Dragon Bloom" \
//   REPLAY_MULTIPASS=1 \
//   [REPLAY_FROM=0 REPLAY_COUNT=90 REPLAY_OUT=/tmp/replay] \
//   swift test --package-path UzumeEngine --filter SessionDrivenMultiPassReplay
import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("SessionDrivenMultiPassReplay")
@MainActor
struct SessionDrivenMultiPassReplay {

    /// Fraction of pixels with any channel at 254+, mean saturation of bright pixels,
    /// and mean luma. The three numbers a "washed out / too bright / too dark" report
    /// is actually about (PR.5).
    struct FrameStats {
        var clipped: Double
        var saturation: Double
        var meanLuma: Double
    }

    private static func stats(_ bgra: [UInt8]) -> FrameStats {
        var clipped = 0, bright = 0
        var sat = 0.0, lum = 0.0
        let count = bgra.count / 4
        guard count > 0 else { return FrameStats(clipped: 0, saturation: 0, meanLuma: 0) }
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let b = Int(bgra[i]), g = Int(bgra[i + 1]), r = Int(bgra[i + 2])
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            lum += (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
            if mx >= 254 { clipped += 1 }
            if mx >= 200 { bright += 1; sat += Double(mx - mn) / Double(mx) }
        }
        return FrameStats(
            clipped: Double(clipped) / Double(count),
            saturation: bright > 0 ? sat / Double(bright) : 0,
            meanLuma: lum / Double(count))
    }

    @Test("replay a recorded session through MultiPassRenderHarness (REPLAY_MULTIPASS=1)")
    func test_replayMultiPass() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["REPLAY_MULTIPASS"] == "1",
              let sessionPath = env["REPLAY_SESSION"],
              let presetName = env["REPLAY_PRESET"] else {
            print("[multipass-replay] set REPLAY_MULTIPASS=1 + REPLAY_SESSION + REPLAY_PRESET")
            return
        }
        let dir = URL(fileURLWithPath: (sessionPath as NSString).expandingTildeInPath)
        let rows = try SessionReplayHarness.loadRowsForReplay(
            dir.appendingPathComponent("features.csv"))
        let stems = SessionReplayHarness.loadStemsForReplay(
            dir.appendingPathComponent("stems.csv"))
        guard !rows.isEmpty else {
            Issue.record("no rows parsed from \(sessionPath)/features.csv"); return
        }

        // Start where audio actually begins; everything before is frozen pre-roll.
        let firstAudio = rows.firstIndex { $0.accumulatedAudioTime > 0 } ?? 0
        let from = Int(env["REPLAY_FROM"] ?? "") ?? firstAudio
        let count = Int(env["REPLAY_COUNT"] ?? "") ?? 120
        let lo = min(from, rows.count - 1)
        let hi = min(lo + count, rows.count)
        let features = Array(rows[lo..<hi]).map {
            SessionReplayHarness.featureForReplay(from: $0, aspect: 1067.0 / 750.0)
        }
        // stems.csv is row-aligned with features.csv; pad with the last row if short.
        let stemSlice: [StemFeatures] = (lo..<hi).map { i in
            stems.isEmpty ? .zero : stems[min(i, stems.count - 1)]
        }
        if stems.isEmpty {
            print("[multipass-replay] WARNING: no stems.csv — stem routes replay against SILENCE")
        }

        print("[multipass-replay] \(presetName): \(features.count) frames "
              + "from row \(lo) (audio starts \(firstAudio)) of \(rows.count)")

        // PR.5: bigger than the 320x180 default when we are going to LOOK at frames
        // rather than only reduce them to three numbers. The stats are the same either
        // way; a contact sheet at 320x180 is not something a trait verdict can be
        // written from.
        let width = Int(env["REPLAY_W"] ?? "") ?? 320
        let height = Int(env["REPLAY_H"] ?? "") ?? 180
        let harness = try MultiPassRenderHarness(width: width, height: height)
        // REPLAY_OUT was documented in this file's usage block from PR.10 and never
        // implemented. Writing every Nth frame is what makes the replay a perception
        // check (D-181) instead of a metric-only run.
        let outDir = (env["REPLAY_OUT"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        if let outDir { try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        let every = Int(env["REPLAY_EVERY"] ?? "") ?? 20
        var frameIndex = 0
        let measured = try harness.render(
            preset: presetName, features: features, stems: stemSlice, settle: 8
        ) { bgra -> FrameStats in
            defer { frameIndex += 1 }
            if let outDir, frameIndex % every == 0 {
                let url = outDir.appendingPathComponent(String(format: "f_%04d.png", frameIndex))
                try? Self.writePNG(bgra: bgra, width: width, height: height, to: url)
            }
            return Self.stats(bgra)
        }
        if let outDir { print("[multipass-replay] frames → \(outDir.path)") }

        guard !measured.isEmpty else { Issue.record("no frames measured"); return }
        let clip = measured.map(\.clipped)
        let sat = measured.map(\.saturation)
        let lum = measured.map(\.meanLuma)
        func mean(_ a: [Double]) -> Double { a.reduce(0, +) / Double(a.count) }
        print("""
        [multipass-replay] \(presetName) over \(measured.count) REAL frames:
          clipped    mean \(String(format: "%.3f", mean(clip)))  max \(String(format: "%.3f", clip.max() ?? 0))
          saturation mean \(String(format: "%.3f", mean(sat)))  min \(String(format: "%.3f", sat.min() ?? 0))
          meanLuma   mean \(String(format: "%.3f", mean(lum)))  max \(String(format: "%.3f", lum.max() ?? 0))
        """)
        // PR.5: the TRAJECTORY, not just the mean. Dragon Bloom's fill is documented as a
        // feedback attractor that develops over ~20 s (DRAGON_BLOOM_PLAN.md L4 item 3), so
        // a single mean cannot tell "converged and wrong" apart from "still filling".
        let bucket = max(1, measured.count / 10)
        var trajectory: [String] = []
        for start in stride(from: 0, to: measured.count, by: bucket) {
            let slice = Array(measured[start..<min(start + bucket, measured.count)])
            trajectory.append(String(format: "%3d:%.2f/%.2f",
                                     start, mean(slice.map(\.clipped)), mean(slice.map(\.saturation))))
        }
        print("  trajectory (frame:clipped/saturation)  " + trajectory.joined(separator: "  "))
        // The harness must not be rendering a dead image — that is the FLY.6 failure.
        #expect(lum.max()! > 0.0, "every frame is pure black — the replay drove nothing")
        #expect(Set(lum.map { Int($0 * 1000) }).count > 1,
                "meanLuma is constant across \(measured.count) frames — the preset is not moving")
    }

    /// BGRA8 bytes → an sRGB PNG. Same recipe as the sketch render tests.
    static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        struct PNGError: Error {}
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw PNGError() }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let made = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: info.rawValue)
            else { return nil }
            return context.makeImage()
        }
        guard let image = made,
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw PNGError() }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw PNGError() }
    }
}
