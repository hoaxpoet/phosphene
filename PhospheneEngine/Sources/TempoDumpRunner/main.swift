// TempoDumpRunner — DSP.1 baseline-capture CLI.
//
// Replays a single audio file through FFTProcessor + BeatDetector at the
// same 1024-sample hop the engine uses, with the dump helper enabled.
// computeStableTempo fires once per second of audio time and writes the
// top-5 IOI bins (BPM, period, count) plus raw/selected BPM to a text
// file. Output is reproducible across runs (same input → same dump).
//
// Usage:
//   .build/release/TempoDumpRunner \
//     --audio-file /path/to/love_rehab.m4a \
//     --label love_rehab \
//     --out docs/diagnostics/DSP.1-baseline-love_rehab.txt
//
// Driver script: Scripts/dump_tempo_baselines.sh runs all three reference
// fixtures and concatenates the per-track files into DSP.1-baseline.txt.

import Foundation
import ArgumentParser
import AVFoundation
import Metal
import Audio
import DSP

@main
struct TempoDumpRunnerCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "TempoDumpRunner",
        abstract: "Replay an audio file through BeatDetector and dump IOI histograms.",
        discussion: """
        Sets BEATDETECTOR_DUMP_HIST=1 and BEATDETECTOR_DUMP_FILE=<out> before
        any BeatDetector access, decodes the audio file to mono Float32,
        then runs FFT + BeatDetector at 1024-sample hops. computeStableTempo
        fires once per second of audio time and dumps top-5 IOI bins.

        For DSP.1 baseline capture, run once per reference track and either
        diff the results or concatenate via Scripts/dump_tempo_baselines.sh.
        """
    )

    @Option(name: .long, help: "Path to audio file (m4a, mp3, wav, etc.).")
    var audioFile: String

    @Option(name: .long, help: "Label written into each dump line (e.g. love_rehab).")
    var label: String

    @Option(name: .long, help: "Output file path. Truncated at start of run.")
    var out: String

    @Option(name: .long, help: "Optional metadata BPM hint (logged only until voting lands).")
    var metadataBpm: Float?

    func run() throws {
        // Set env vars BEFORE any BeatDetector access. The diagnostic
        // helper resolves these once via static let on first dump call.
        setenv("BEATDETECTOR_DUMP_HIST", "1", 1)
        setenv("BEATDETECTOR_DUMP_FILE", out, 1)

        let url = URL(fileURLWithPath: audioFile)
        print("TempoDumpRunner: decoding \(audioFile)")
        let (samples, sampleRate) = try decodeMonoFloat32(url: url)
        let durationSec = Float(samples.count) / sampleRate
        let durStr = String(format: "%.1f", durationSec)
        print("TempoDumpRunner: \(samples.count) samples @ \(Int(sampleRate)) Hz (\(durStr)s)")

        // Truncate output and write a header line so per-track sections
        // are obvious in the concatenated baseline file.
        try truncateAndWriteHeader(HeaderInfo(
            path: out,
            label: label,
            file: audioFile,
            sampleRate: sampleRate,
            durationSec: durationSec,
            metadataBpm: metadataBpm
        ))

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("TempoDumpRunner: no Metal device available")
            throw ExitCode(1)
        }

        let fft = try FFTProcessor(device: device)
        let beatDetector = BeatDetector(
            binCount: 512, sampleRate: sampleRate, fftSize: 1024
        )
        if let bpm = metadataBpm {
            print("TempoDumpRunner: metadata BPM=\(bpm) (no-op until voting lands)")
        }

        runAnalysisLoop(
            samples: samples, sampleRate: sampleRate, fft: fft, beatDetector: beatDetector
        )

        print("TempoDumpRunner: complete → \(out)")
    }

    private func runAnalysisLoop(
        samples: [Float],
        sampleRate: Float,
        fft: FFTProcessor,
        beatDetector: BeatDetector
    ) {
        let hop = 1024
        let fps = sampleRate / Float(hop)
        let deltaTime = Float(hop) / sampleRate
        var offset = 0
        var elapsedSec: Float = 0
        var lastSecondDumped = -1
        while offset + hop <= samples.count {
            let window = Array(samples[offset..<offset + hop])
            _ = fft.process(samples: window, sampleRate: sampleRate)
            let mags = Array(fft.magnitudeBuffer.pointer)
            let result = beatDetector.process(
                magnitudes: mags, fps: fps, deltaTime: deltaTime
            )
            elapsedSec += deltaTime
            for bandIdx in result.onsets.indices where result.onsets[bandIdx] {
                let onsetFmt = "[DSP.1 onset] band=%d t=%.4f"
                appendLine(path: out, line: String(format: onsetFmt, bandIdx, elapsedSec))
            }
            let currentSecond = Int(elapsedSec)
            if currentSecond > lastSecondDumped {
                lastSecondDumped = currentSecond
                let acFmt = "[DSP.1 dump] autocorr bpm=%.2f conf=%.3f stable=%.0f instant=%.0f"
                let acLine = String(
                    format: acFmt,
                    result.estimatedTempo ?? 0,
                    result.tempoConfidence,
                    result.stableBPM,
                    result.instantBPM
                )
                appendLine(path: out, line: acLine)
            }
            offset += hop
        }
    }

    private func appendLine(path: String, line: String) {
        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    private func decodeMonoFloat32(url: URL) throws -> (samples: [Float], sampleRate: Float) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw ValidationError("audio file is empty")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ValidationError("failed to allocate AVAudioPCMBuffer")
        }
        try file.read(into: buffer)

        let actualFrames = Int(buffer.frameLength)
        guard actualFrames > 0, let channelData = buffer.floatChannelData else {
            throw ValidationError("decode produced no samples")
        }
        let channelCount = Int(format.channelCount)

        var samples: [Float]
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: actualFrames))
        } else {
            samples = [Float](repeating: 0, count: actualFrames)
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                let ptr = UnsafeBufferPointer(start: channelData[ch], count: actualFrames)
                for i in 0..<actualFrames {
                    samples[i] += ptr[i] * scale
                }
            }
        }
        return (samples, Float(format.sampleRate))
    }

    private struct HeaderInfo {
        let path: String
        let label: String
        let file: String
        let sampleRate: Float
        let durationSec: Float
        let metadataBpm: Float?
    }

    private func truncateAndWriteHeader(_ info: HeaderInfo) throws {
        let url = URL(fileURLWithPath: info.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
        let bpmStr = info.metadataBpm.map { String(format: "%.1f", $0) } ?? "none"
        let fmt = "===== %@ file=%@ rate=%.0f duration=%.1fs metadataBPM=%@ =====\n"
        let header = String(
            format: fmt,
            info.label,
            info.file,
            info.sampleRate,
            info.durationSec,
            bpmStr
        )
        if let data = header.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }
}
