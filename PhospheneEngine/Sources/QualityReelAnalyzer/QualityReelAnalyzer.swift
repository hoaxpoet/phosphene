// QualityReelAnalyzer — Offline beat-reactivity analysis for Phosphene quality reels.
//
// Given a reel video (mp4 / mov), runs the audio track through Phosphene's
// Beat This! pipeline (BeatThisPreprocessor → BeatThisModel → BeatGridResolver)
// to produce an authoritative BeatGrid, then samples video frames at every
// beat timestamp plus midpoint control frames between consecutive beats and
// computes per-frame luma statistics. Outputs a Markdown report comparing
// beat-frame luma to midpoint-frame luma — a "reactivity ratio" >> 1 means the
// rendered visual is responding to beats; ratio ≈ 1 means it is not.
//
// External dependency: ffmpeg on PATH (audio extraction + frame sampling).
//
// Usage:
//   .build/release/QualityReelAnalyzer \
//     --reel docs/quality_reel.mp4 \
//     --out  docs/quality_reel_report.md \
//     --frames-dir /tmp/quality_reel_frames \
//     --max-beats 200

import Foundation
import ArgumentParser
import AVFoundation
import CoreGraphics
import ImageIO
import Metal
import DSP
import ML

@main
struct QualityReelAnalyzerCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "QualityReelAnalyzer",
        abstract: "Beat-reactivity analysis of a Phosphene quality reel."
    )

    @Option(name: .long, help: "Path to reel video file (mp4, mov, etc.).")
    var reel: String

    @Option(
        name: .long,
        help: "Optional separate audio file (wav, m4a). When given, audio is "
            + "extracted from it rather than from --reel. Pair Phosphene's own "
            + "session outputs: --reel video.mp4 --audio raw_tap.wav."
    )
    var audio: String?

    @Option(name: .long, help: "Output Markdown report path.")
    var out: String

    @Option(name: .long, help: "Directory for per-beat frame PNGs (created if missing).")
    var framesDir: String

    @Option(name: .long, help: "Cap on beats analyzed (frames extracted = 2 × this). Default 200.")
    var maxBeats: Int = 200

    @Flag(name: .long, help: "Skip frame extraction; report audio-side beat grid only.")
    var audioOnly: Bool = false

    func run() throws {
        try FFmpegBridge.ensureAvailable()

        let reelURL = URL(fileURLWithPath: reel)
        guard FileManager.default.fileExists(atPath: reelURL.path) else {
            throw ValidationError("reel file not found: \(reel)")
        }
        let framesURL = URL(fileURLWithPath: framesDir)
        try FileManager.default.createDirectory(
            at: framesURL, withIntermediateDirectories: true
        )

        let audioSourceURL: URL
        if let audioPath = audio {
            let url = URL(fileURLWithPath: audioPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("audio file not found: \(audioPath)")
            }
            audioSourceURL = url
        } else {
            audioSourceURL = reelURL
        }
        let samples = try extractSamples(audioSourceURL: audioSourceURL)
        let durationSec = Double(samples.count) / 22050.0
        print("[QRA] audio: \(samples.count) samples (\(String(format: "%.1f", durationSec))s)")

        let grid = try runBeatThis(samples: samples)
        let bpmStr = String(format: "%.1f", grid.bpm)
        print(
            "[QRA] BeatGrid: \(grid.beats.count) beats, "
            + "\(grid.downbeats.count) downbeats, \(bpmStr) BPM, \(grid.beatsPerBar)/X"
        )

        var beatLumas: [Double] = []
        var midLumas: [Double] = []
        if !audioOnly && !grid.beats.isEmpty {
            print("[QRA] sampling video frames …")
            let sampled = try FrameSampler.sample(
                reel: reelURL,
                framesDir: framesURL,
                beats: grid.beats,
                cap: maxBeats
            )
            beatLumas = sampled.beatLumas
            midLumas = sampled.midLumas
            print(
                "[QRA] sampled \(beatLumas.count) beat frames, "
                + "\(midLumas.count) midpoints"
            )
        }

        let context = ReportContext(
            outPath: out,
            reelPath: reel,
            durationSec: durationSec,
            grid: grid,
            beatLumas: beatLumas,
            midLumas: midLumas,
            framesDir: framesDir,
            audioOnly: audioOnly
        )
        try ReportWriter.write(context: context)
        print("[QRA] report → \(out)")
    }

    private func extractSamples(audioSourceURL: URL) throws -> [Float] {
        print("[QRA] extracting audio from \(audioSourceURL.lastPathComponent) at 22050 Hz mono …")
        let audioURL = try FFmpegBridge.extractAudio(reel: audioSourceURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        return try FFmpegBridge.readFloat32Mono(url: audioURL)
    }

    private func runBeatThis(samples: [Float]) throws -> BeatGrid {
        print("[QRA] running BeatThisPreprocessor …")
        let pre = BeatThisPreprocessor()
        let (spect, frameCount) = pre.process(
            samples: samples, inputSampleRate: 22050.0
        )
        print("[QRA] spectrogram: \(frameCount) frames × 128 mels")

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RuntimeError("no Metal device available")
        }
        print("[QRA] running BeatThisModel.predict …")
        let model = try BeatThisModel(device: device)
        let predStart = Date()
        let (beatProbs, downbeatProbs) = try model.predict(
            spectrogram: spect, frameCount: frameCount
        )
        let predMs = String(format: "%.0f", Date().timeIntervalSince(predStart) * 1000)
        print("[QRA] inference complete in \(predMs) ms")

        return BeatGridResolver.resolve(
            beatProbs: beatProbs,
            downbeatProbs: downbeatProbs,
            frameRate: 50.0
        )
    }
}

// MARK: - FFmpeg

private enum FFmpegBridge {

    static func ensureAvailable() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "ffmpeg"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw RuntimeError("ffmpeg not found on PATH (install via `brew install ffmpeg`)")
        }
    }

    static func extractAudio(reel: URL) throws -> URL {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let outURL = tmpDir.appendingPathComponent("qra_audio_\(UUID().uuidString).pcm")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error", "-y",
            "-i", reel.path,
            "-ac", "1", "-ar", "22050", "-f", "f32le",
            outURL.path
        ]
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw RuntimeError(
                "ffmpeg audio extraction failed (exit \(proc.terminationStatus))"
            )
        }
        return outURL
    }

    static func readFloat32Mono(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { rawBuf in
            let typed = rawBuf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }

    static func extractFrame(reel: URL, atSeconds time: Double, outURL: URL) throws -> Bool {
        let tStr = String(format: "%.4f", time)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error", "-y",
            "-ss", tStr,
            "-i", reel.path,
            "-frames:v", "1",
            "-q:v", "3",
            outURL.path
        ]
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
            && FileManager.default.fileExists(atPath: outURL.path)
    }
}

// MARK: - Frame Sampling + Luma

private enum FrameSampler {

    struct SampleSet {
        let beatLumas: [Double]
        let midLumas: [Double]
    }

    static func sample(
        reel: URL,
        framesDir: URL,
        beats: [Double],
        cap: Int
    ) throws -> SampleSet {
        let limit = min(cap, beats.count - 1)
        var beatLumas: [Double] = []
        var midLumas: [Double] = []

        for idx in 0..<limit {
            let beatT = beats[idx]
            let nextT = beats[idx + 1]
            let midT = (beatT + nextT) * 0.5

            let beatFile = framesDir.appendingPathComponent(
                String(format: "beat_%04d_t%.3f.png", idx, beatT)
            )
            let midFile = framesDir.appendingPathComponent(
                String(format: "mid_%04d_t%.3f.png", idx, midT)
            )

            if try FFmpegBridge.extractFrame(reel: reel, atSeconds: beatT, outURL: beatFile),
               let luma = meanLuma(of: beatFile) {
                beatLumas.append(luma)
            }
            if try FFmpegBridge.extractFrame(reel: reel, atSeconds: midT, outURL: midFile),
               let luma = meanLuma(of: midFile) {
                midLumas.append(luma)
            }
            if idx % 25 == 0 {
                print("[QRA]  frame \(idx)/\(limit) …")
            }
        }
        return SampleSet(beatLumas: beatLumas, midLumas: midLumas)
    }

    private static func meanLuma(of url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: info
        ) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total: Double = 0
        var count = 0
        for yIdx in 0..<height {
            for xIdx in 0..<width {
                let off = yIdx * bytesPerRow + xIdx * bytesPerPixel
                let red = Double(pixels[off])
                let grn = Double(pixels[off + 1])
                let blu = Double(pixels[off + 2])
                total += 0.2126 * red + 0.7152 * grn + 0.0722 * blu
                count += 1
            }
        }
        return total / Double(count) / 255.0
    }
}

// MARK: - Errors

struct RuntimeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
