// BeatThisActivationDumper — Swift counterpart to Scripts/dump_beatthis_activations.py.
//
// Runs BeatThisModel on a given audio file, captures every intermediate
// tensor exposed via BeatThisGraphBundle.intermediates, dumps per-stage
// stats matching the Python schema. The two JSONs are then diffed by
// Scripts/diff_beatthis_activations.py to localise the first divergence.
//
// File is named Dumper.swift (not main.swift) to avoid Swift's script-mode
// parsing kicking in when @main + sibling files are present.

import Foundation
import ArgumentParser
import AVFoundation
import Metal
import DSP
import ML

@main
struct BeatThisActivationDumperCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "BeatThisActivationDumper",
        abstract: "Dump intermediate BeatThisModel activations on a given audio file."
    )

    @Option(name: .long, help: "Path to audio file (m4a / wav / mp3).")
    var audio: String

    @Option(name: .long, help: "Output JSON path.")
    var out: String

    @Option(name: .long,
            help: "Optional directory for full Float32 tensor dumps as raw .bin (row-major).")
    var rawDir: String?

    func run() throws {
        let audioURL = URL(fileURLWithPath: audio)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ValidationError("audio file not found: \(audio)")
        }
        print("[BTAD] decoding \(audioURL.lastPathComponent) at 22050 Hz mono …")
        let samples = try ffmpegDecodeMono22050(url: audioURL)
        let durStr = String(format: "%.1f", Double(samples.count) / 22050.0)
        print("[BTAD] audio: \(samples.count) samples / \(durStr)s")

        let pre = BeatThisPreprocessor()
        let (spect, frameCount) = pre.process(samples: samples, inputSampleRate: 22050.0)
        print("[BTAD] spectrogram: \(frameCount) frames × 128 mels")

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("no Metal device available")
        }
        let model = try BeatThisModel(device: device)

        print("[BTAD] running predictDiagnostic …")
        let captures = try model.predictDiagnostic(spectrogram: spect, frameCount: frameCount)
        print("[BTAD] captured \(captures.count) intermediate stages")

        if let rawDirPath = rawDir {
            let rawURL = URL(fileURLWithPath: rawDirPath)
            try FileManager.default.createDirectory(
                at: rawURL, withIntermediateDirectories: true
            )
            for (name, capture) in captures {
                let fileURL = rawURL.appendingPathComponent("\(name).bin")
                let data = capture.values.withUnsafeBufferPointer {
                    Data(buffer: $0)
                }
                try data.write(to: fileURL)
            }
            print("[BTAD] wrote \(captures.count) raw tensors → \(rawDirPath)")
        }

        let payload = makePayload(audioPath: audio, captures: captures)
        let outURL = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try json.write(to: outURL)
        print("[BTAD] wrote → \(out)")
    }

    private func makePayload(
        audioPath: String,
        captures: [String: (shape: [Int], values: [Float])]
    ) -> [String: Any] {
        let stages: [[String: Any]] = captures
            .sorted { $0.key < $1.key }
            .map { name, capture in
                let values = capture.values
                let count = values.count
                let lo = values.min() ?? 0
                let hi = values.max() ?? 0
                let sum = values.reduce(Float(0), +)
                let mean = count > 0 ? sum / Float(count) : 0
                let variance = values.reduce(Float(0)) { acc, val in
                    acc + (val - mean) * (val - mean)
                } / Float(max(count, 1))
                let std = variance.squareRoot()
                let first32 = Array(values.prefix(32)).map { Double($0) }
                let last32 = Array(values.suffix(32)).map { Double($0) }
                return [
                    "name": name,
                    "shape": capture.shape,
                    "min": Double(lo),
                    "max": Double(hi),
                    "mean": Double(mean),
                    "std": Double(std),
                    "first32": first32,
                    "last32": last32
                ]
            }
        return [
            "source": audioPath,
            "variant": "small0",
            "n_stages": stages.count,
            "stages": stages
        ]
    }

    private func ffmpegDecodeMono22050(url: URL) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1", "-ar", "22050",
            "-f", "f32le", "-"
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        try proc.run()
        let raw = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ValidationError("ffmpeg decode failed (exit \(proc.terminationStatus))")
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }
}
