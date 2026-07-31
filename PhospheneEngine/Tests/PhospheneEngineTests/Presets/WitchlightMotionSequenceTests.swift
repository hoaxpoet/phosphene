// WitchlightMotionSequenceTests — the pre-M7 motion dump.
//
// D-209 §6 rated the harmonic-state→pen-path mechanism level 3 and made a
// motion-gated look-spike WL.2's first deliverable. The D-209 amendment cites the
// resulting motion verdict as the evidence that discharges the level-3 rating on
// the COMBINATION — so this harness has to live in the repo, or that claim is not
// reproducible.
//
// It renders a contiguous frame sequence through the production particle path
// (`MultiPassRenderHarness.renderWitchlight` → `WitchlightStroke.update` → `.render`,
// the same calls the app makes) and writes PNGs for `Scripts/motion_gate.sh` to turn
// into a frame-to-frame motion signal (D-195). The smooth / jitter / off-concept
// VERDICT is the reader's — the spike count is evidence, not an auto-pass (D-064).
//
// Driven by the COMMITTED real-music fixtures via `WitchlightFixtureDrive`, not by
// hand-authored envelopes (FA #27) and not by external session captures: the whole
// question is whether real harmonic motion draws a legible figure, and the answer
// has to be reproducible by anyone with a checkout.
//
//   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
//       --filter WitchlightMotionSequence
//   Scripts/motion_gate.sh witchlight /tmp/phosphene_visual/<stamp>/<track>
//
// Sequence-not-stills is the point: Truchet Loom passed still review and jittered
// "like a bug" in live M7 (D-194).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Renderer
@testable import Shared

@MainActor
@Suite("Witchlight motion sequence (pre-M7 gate)")
struct WitchlightMotionSequenceTests {

    private static let outputRoot = "/tmp/phosphene_visual"
    private let width = 960
    private let height = 540

    @Test("Render Witchlight motion sequences from the committed fixtures (RENDER_VISUAL=1)")
    func renderWitchlightMotionSequences() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[witchlight] RENDER_VISUAL not set — skipping motion-sequence dump")
            return
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let root = URL(fileURLWithPath: Self.outputRoot).appendingPathComponent(stamp)
        let harness = MultiPassRenderHarness(width: width, height: height)

        for track in WitchlightFixtureDrive.tracks {
            let drive = try WitchlightFixtureDrive.load(track, aspect: Float(width) / Float(height))
            guard drive.features.count > 60 else {
                print("[witchlight] \(track): only \(drive.features.count) frames — skipped")
                continue
            }

            let frames: [[UInt8]] = try harness.render(
                preset: "Witchlight", features: drive.features, stems: drive.stems, settle: 0
            ) { $0 }

            let dir = root.appendingPathComponent(track)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (index, bgra) in frames.enumerated() {
                try Self.writePNG(
                    bgra: bgra, width: width, height: height,
                    to: dir.appendingPathComponent(String(format: "witchlight_seq_%04d.png", index)))
            }

            // Non-degenerate guard. A frozen or blank sequence would make the motion gate
            // read "smooth" for the wrong reason, and the reader must not have to discover
            // that by eye. This caught a real regression once: a camera-framing change that
            // walked the figure off-screen produced a perfectly smooth run of black frames.
            let spread = Self.frameSpread(frames)
            print("""
                [witchlight] \(track): \(frames.count) frames → \(dir.path)
                             mean |Δframe| = \(String(format: "%.5f", spread.mean)), \
                max = \(String(format: "%.5f", spread.max)), \
                non-black pixels (last frame) = \(spread.lastNonBlack)
                """)
            #expect(spread.mean > 0.0, "\(track): sequence is frozen — every frame identical")
            #expect(spread.lastNonBlack > 0, "\(track): final frame is entirely black — nothing drawn")
        }

        print("""
            [witchlight] motion-sequence root: \(root.path)
                         next: Scripts/motion_gate.sh witchlight <root>/<track>
                         then READ the sampled frames as a sequence and write the motion verdict.
            """)
    }

    // MARK: - Frame statistics

    /// Mean and max normalised absolute frame-to-frame difference, plus the non-black
    /// pixel count of the final frame.
    private static func frameSpread(_ frames: [[UInt8]]) -> (mean: Double, max: Double, lastNonBlack: Int) {
        guard frames.count > 1 else { return (0, 0, 0) }
        var deltas: [Double] = []
        deltas.reserveCapacity(frames.count - 1)
        for (a, b) in zip(frames, frames.dropFirst()) {
            var sum = 0.0
            for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
                sum += abs(Double(a[i]) - Double(b[i]))
                    + abs(Double(a[i + 1]) - Double(b[i + 1]))
                    + abs(Double(a[i + 2]) - Double(b[i + 2]))
            }
            deltas.append(sum / Double(max(1, a.count / 4)) / 255.0)
        }
        let last = frames[frames.count - 1]
        var nonBlack = 0
        for i in stride(from: 0, to: last.count, by: 4) where last[i] > 8 || last[i + 1] > 8 || last[i + 2] > 8 {
            nonBlack += 1
        }
        return (deltas.reduce(0, +) / Double(deltas.count), deltas.max() ?? 0, nonBlack)
    }

    // MARK: - PNG

    private static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        var pixels = bgra
        let info: CGBitmapInfo = [
            .byteOrder32Little,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        ]
        guard let provider = CGDataProvider(data: Data(bytes: &pixels, count: pixels.count) as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WitchlightSequenceError.pngWriteFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw WitchlightSequenceError.pngWriteFailed }
    }
}

enum WitchlightSequenceError: Error { case pngWriteFailed }
