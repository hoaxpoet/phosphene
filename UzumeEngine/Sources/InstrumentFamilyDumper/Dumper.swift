// InstrumentFamilyDumper — IFC.5 (D-177) diagnostic surface for instrument-family capture.
// STATUS: retained-diagnostic — standalone CLI (executableTarget), run ad hoc on an
//   orchestral clip to eyeball per-family activity firing. Zero production importers
//   BY DESIGN (like BeatThisActivationDumper); the production path is
//   SessionPreparer.analyzePreview. See docs/AUDIT_KEEPLIST.md.
//
// Decodes an audio file to mono 44.1 kHz (the preview-native rate) and runs the
// PRODUCTION InstrumentFamilyAnalyzer — exercising the resample (44.1 → 32 kHz),
// 2 s/1 s windowing, PANNs sweep, and D-026 tracker exactly as analyzePreview does
// (IFC.2's numerical parity fed 32 kHz directly and did NOT cover the resample).
// Prints a per-window activity table + a "leader per window" summary so the
// string-dominant / brass↔woodwind-trading discrimination is readable, mirroring
// the 2026-06-29 spike (scoping §3).
//
// File named Dumper.swift (not main.swift) to avoid Swift script-mode parsing.

import ArgumentParser
import AVFoundation
import Foundation
import Metal
import ML

@main
struct InstrumentFamilyDumperCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "InstrumentFamilyDumper",
        abstract: "Dump per-family instrument activity (strings/brass/woodwinds/percussion) over a clip."
    )

    @Option(name: .long, help: "Path to audio file (m4a / wav / mp3 / flac).")
    var audio: String

    @Option(name: .long, help: "Optional start offset in seconds (default 0).")
    var start: Double = 0

    @Option(name: .long, help: "Optional duration in seconds (default: whole file).")
    var duration: Double?

    @Option(name: .long, help: "Optional JSON output path for the per-window series.")
    var out: String?

    func run() throws {
        let audioURL = URL(fileURLWithPath: audio)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ValidationError("audio file not found: \(audio)")
        }
        // Decode to the preview-native 44.1 kHz so the analyzer's resample runs.
        let sr = 44_100
        print("[IFD] decoding \(audioURL.lastPathComponent) at \(sr) Hz mono …")
        let samples = try ffmpegDecodeMono(url: audioURL, sampleRate: sr, start: start, duration: duration)
        let durStr = String(format: "%.1f", Double(samples.count) / Double(sr))
        print("[IFD] audio: \(samples.count) samples / \(durStr)s")

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("no Metal device available")
        }
        let analyzer = try InstrumentFamilyAnalyzer(device: device)

        print("[IFD] running InstrumentFamilyAnalyzer (2 s window / 1 s hop) …")
        let series = analyzer.analyzeFamilyActivity(samples: samples, sampleRate: Double(sr))
        guard !series.isEmpty else {
            throw ValidationError("clip shorter than one 2 s window — no activity produced")
        }
        print("[IFD] \(series.count) windows\n")

        printTable(series)
        if let outPath = out { try writeJSON(series, to: outPath) }
    }

    // MARK: - Reporting

    private func printTable(_ series: [InstrumentFamilyActivity]) {
        let hop = InstrumentFamilyAnalyzer.hopSeconds
        print("  t(s) | strings         | brass           | woodwinds       | percussion      | leader")
        print("  -----+-----------------+-----------------+-----------------+-----------------+---------")
        for (i, win) in series.enumerated() {
            let tStr = String(format: "%4.0f", Double(i) * hop)
            let cells = InstrumentFamily.allCases.map { fam -> String in
                let reading = win[fam]
                return String(format: "%.2f/%.2f", reading.smoothed, reading.dev)  // smoothed / dev
            }
            // Leader = family with the highest positive deviation (the trigger).
            let leaderIdx = (0..<win.dev.count).max(by: { win.dev[$0] < win.dev[$1] }) ?? 0
            let leader = win.dev[leaderIdx] > 1e-4 ? InstrumentFamily.allCases[leaderIdx].rawValue : "—"
            let row = cells.map { $0.padding(toLength: 15, withPad: " ", startingAt: 0) }
                .joined(separator: " | ")
            print("  \(tStr) | \(row) | \(leader)")
        }
        print("\n  (cells are smoothed/dev; leader = family with the largest positive D-026 deviation)")
    }

    private func writeJSON(_ series: [InstrumentFamilyActivity], to path: String) throws {
        let hop = InstrumentFamilyAnalyzer.hopSeconds
        let windows: [[String: Any]] = series.enumerated().map { i, win in
            var family: [String: [String: Double]] = [:]
            for fam in InstrumentFamily.allCases {
                let reading = win[fam]
                family[fam.rawValue] = [
                    "raw": Double(reading.raw), "smoothed": Double(reading.smoothed), "dev": Double(reading.dev)]
            }
            return ["t": Double(i) * hop, "family": family]
        }
        let payload: [String: Any] = ["source": audio, "hop_s": hop, "windows": windows]
        let outURL = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: outURL)
        print("[IFD] wrote series → \(path)")
    }

    // MARK: - Decode

    private func ffmpegDecodeMono(url: URL, sampleRate: Int, start: Double, duration: Double?) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["ffmpeg", "-loglevel", "error", "-ss", String(start), "-i", url.path]
        if let duration { args += ["-t", String(duration)] }
        args += ["-ac", "1", "-ar", String(sampleRate), "-f", "f32le", "-"]
        proc.arguments = args
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
