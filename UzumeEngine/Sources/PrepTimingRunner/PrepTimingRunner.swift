// PrepTimingRunner — PREP.1 preparation-cost measurement CLI.
//
// D-242 set a 7.5 s/track budget for session preparation and recorded that
// nobody knows which stage spends the 50 s/track the local path actually
// costs. This runs the shipping pipeline — `LocalFilePreparationPipeline`,
// the same code `VisualizerEngine.prepareLocalFile(url:)` calls — over a list
// of audio files with `UZUME_PREP_TIMING=1`, and writes the per-stage
// `preparation.csv` plus a summary to stdout.
//
// It exists because the alternative is driving the GUI, and because a runner
// that re-implements the stage list measures a copy of the pipeline rather
// than the pipeline. Nothing here decides what the pipeline does; it only
// supplies the dependencies the app layer normally supplies.
//
// Usage:
//
//   swift run -c release PrepTimingRunner \
//     --cache /tmp/prep-cold --out /tmp/prep-run-1 \
//     "/path/to/01.flac" "/path/to/02.flac" …
//
//   # streaming control — the shared analyzePreview over a 30 s window
//   swift run -c release PrepTimingRunner --preview-seconds 30 …
//
//   # does running two tracks at once overlap, or merely contend?
//   swift run -c release PrepTimingRunner --concurrency 2 …
//
// `--cache` MUST be a scratch directory. The runner never writes to the real
// `~/Library/Application Support/Uzume/StemCache`; a cold run is the point,
// and Matt's cache is not test scaffolding.

import ArgumentParser
import Audio
import DSP
import Foundation
import ML
import Metal
import Session
import Shared

// MARK: - Command

@main
struct PrepTimingRunner: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "prep-timing-runner",
        abstract: "Time every stage of session preparation over a list of audio files (PREP.1 / D-242)."
    )

    @Argument(help: "Audio files to prepare, in order.")
    var files: [String] = []

    @Option(name: .long, help: "Folder to take audio files from instead of listing them.")
    var folder: String?

    @Option(name: .long, help: "Scratch directory for the cold persistent stem cache. REQUIRED.")
    var cache: String

    @Option(name: .long, help: "Directory to write preparation.csv into.")
    var out: String

    @Option(name: .long, help: "Tracks prepared at once. 1 (default) is the shipping serial loop.")
    var concurrency: Int = 1

    @Option(name: .long, help: "Stop after this many files.")
    var limit: Int?

    @Option(
        name: .long,
        help: "Streaming control: analyse only the first N seconds through the shared analyzePreview."
    )
    var previewSeconds: Double?

    @Flag(name: .long, help: "Write the summary to disk only; no progress on stderr.")
    var quiet: Bool = false

    @Flag(
        name: .long,
        help: "Run with the timing probe OFF, to measure what the instrumentation itself costs."
    )
    var disableProbe: Bool = false

    // MARK: Run

    mutating func run() async throws {
        guard PrepStageSink.isEnabled || disableProbe else {
            throw ValidationError(
                "UZUME_PREP_TIMING=1 must be set — the timing probe is gated on it. "
                + "Re-run as: UZUME_PREP_TIMING=1 swift run …"
            )
        }

        let urls = try resolveInputs()
        guard !urls.isEmpty else { throw ValidationError("no input files") }

        let cacheRoot = URL(fileURLWithPath: cache, isDirectory: true)
        try assertScratch(cacheRoot)
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("no Metal device")
        }

        // --disable-probe is how the gate gets proved with a number rather than
        // an assertion: same files, same build, probe off.
        let sink = disableProbe
            ? nil
            : PrepStageSink(destination: outDir.appendingPathComponent("preparation.csv"))
        let workers = try (0..<max(1, concurrency)).map { _ in
            try Worker(device: device, cacheRoot: cacheRoot)
        }

        note("prep-timing: \(urls.count) file(s) · concurrency=\(concurrency)"
            + (previewSeconds.map { " · preview-window=\($0)s" } ?? " · full local pipeline")
            + " · cache=\(cacheRoot.path)")

        let started = Date()
        if concurrency <= 1 {
            for (index, url) in urls.enumerated() {
                try await prepare(url, worker: workers[0], sink: sink, index: index, of: urls.count)
            }
        } else {
            try await runConcurrently(urls: urls, workers: workers, sink: sink)
        }
        let wall = Date().timeIntervalSince(started)

        sink?.flush()
        Summary(rows: sink?.snapshot ?? [], wallSeconds: wall, trackCount: urls.count)
            .write(to: outDir.appendingPathComponent("summary.txt"), alsoPrinting: !quiet)
    }

    // MARK: One track

    private func prepare(
        _ url: URL,
        worker: Worker,
        sink: PrepStageSink?,
        index: Int,
        of total: Int
    ) async throws {
        let name = url.lastPathComponent
        let started = Date()
        if let previewSeconds {
            try worker.runPreviewControl(url: url, seconds: previewSeconds, sink: sink)
        } else {
            _ = await LocalFilePreparationPipeline.run(inputs: worker.inputs(for: url, sink: sink))
        }
        let elapsed = Date().timeIntervalSince(started)
        note(String(format: "  [%d/%d] %@  %.1f s", index + 1, total, name, elapsed))
    }

    /// Concurrency is a MEASUREMENT here, never a pipeline change: the shipping
    /// loop in `SessionPreparer._runLocalFilePreparation` stays strictly serial.
    /// This mode exists to answer whether two tracks at once would overlap or
    /// merely contend — task 3's question — with a wall-clock number instead of
    /// an inference from CPU percentages.
    private func runConcurrently(urls: [URL], workers: [Worker], sink: PrepStageSink?) async throws {
        var next = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (slot, worker) in workers.enumerated() where slot < urls.count {
                let url = urls[next]
                let index = next
                next += 1
                group.addTask { [self] in
                    try await prepare(url, worker: worker, sink: sink, index: index, of: urls.count)
                }
            }
            var slot = 0
            while try await group.next() != nil {
                guard next < urls.count else { continue }
                let url = urls[next]
                let index = next
                next += 1
                let worker = workers[slot % workers.count]
                slot += 1
                group.addTask { [self] in
                    try await prepare(url, worker: worker, sink: sink, index: index, of: urls.count)
                }
            }
        }
    }

    // MARK: Inputs

    private func resolveInputs() throws -> [URL] {
        var urls = files.map { URL(fileURLWithPath: $0) }
        if let folder {
            let dir = URL(fileURLWithPath: folder, isDirectory: true)
            let contents = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            let audio: Set<String> = ["flac", "m4a", "mp3", "wav", "aiff", "aif", "aac", "alac"]
            urls += contents
                .filter { audio.contains($0.pathExtension.lowercased()) }
                .filter { !$0.lastPathComponent.hasPrefix("._") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if let limit { urls = Array(urls.prefix(limit)) }
        return urls
    }

    /// A cold run means an empty cache, and an empty cache means the runner is
    /// allowed to create and fill this directory. Refuse anything that looks
    /// like the real one.
    private func assertScratch(_ root: URL) throws {
        let real = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        if let real, root.standardizedFileURL.path.hasPrefix(real.standardizedFileURL.path) {
            throw ValidationError(
                "--cache points inside Application Support (\(root.path)). "
                + "Use a scratch directory; the user's real stem cache is never a test fixture.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func note(_ line: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

// MARK: - Worker

/// One set of the ML dependencies `VisualizerEngine` normally owns. At
/// `--concurrency N` there are N of these, which is what N parallel prepare
/// tasks would need: `StemSeparator` serialises internally (BUG-031), so
/// sharing one would measure the lock rather than the hardware.
private final class Worker: @unchecked Sendable {
    let separator: StemSeparator
    let beatGrid: DefaultBeatGridAnalyzer
    let family: InstrumentFamilyAnalyzer
    let classifier: MoodClassifier
    let cache: PersistentStemCache

    init(device: MTLDevice, cacheRoot: URL) throws {
        separator = try StemSeparator(device: device)
        beatGrid = try DefaultBeatGridAnalyzer(device: device)
        family = try InstrumentFamilyAnalyzer(device: device)
        classifier = MoodClassifier()
        cache = try PersistentStemCache(rootDirectory: cacheRoot)
    }

    func inputs(for url: URL, sink: PrepStageSink?) -> LocalFilePrepWorkerInputs {
        LocalFilePrepWorkerInputs(
            url: url,
            filename: url.lastPathComponent,
            separator: separator,
            analyzer: StemAnalyzer(),
            classifier: classifier,
            beatGridAnalyzer: beatGrid,
            familyAnalyzer: family,
            persistentCache: cache,
            recorder: nil,
            timingSink: sink
        )
    }

    /// The streaming control (PREP.1 task 6). Streaming downloads a 30 s
    /// preview and runs `SessionPreparer.analyzePreview` on it — the same call
    /// the local path makes, minus the two whole-file extras. Decoding a local
    /// file and truncating to the same window isolates the shared analysis cost
    /// from the whole-file cost, on identical material.
    func runPreviewControl(url: URL, seconds: Double, sink: PrepStageSink?) throws {
        let name = url.lastPathComponent
        var probe = PrepStageProbe(sink: sink, track: name)
        let trackStart = Date()
        let trackCPU0 = PrepStageSink.cpuSeconds()

        let full = try probe.measure(PrepStage.decode) {
            try PreviewAudio.fromLocalFile(at: url)
        }
        let wanted = min(full.pcmSamples.count, Int(seconds * Double(full.sampleRate)))
        let window = PreviewAudio(
            trackIdentity: full.trackIdentity,
            pcmSamples: Array(full.pcmSamples.prefix(wanted)),
            sampleRate: full.sampleRate,
            duration: Double(wanted) / Double(full.sampleRate)
        )
        probe = probe.notingAudioSeconds(window.duration)

        _ = try SessionPreparer.analyzePreview(
            window,
            separator: separator,
            analyzer: StemAnalyzer(),
            classifier: classifier,
            beatGridAnalyzer: beatGrid,
            familyAnalyzer: family,
            prefetchedProfile: nil,
            probe: probe
        )
        probe.record(
            PrepStage.trackTotal,
            wallMs: Date().timeIntervalSince(trackStart) * 1000,
            cpuMs: (PrepStageSink.cpuSeconds() - trackCPU0) * 1000
        )
    }
}

// MARK: - Summary

/// Everything the report's tables need, derived from the rows rather than
/// recomputed by hand: per-stage share of wall clock, cores held, and cost per
/// second of decoded audio.
struct Summary {
    let rows: [PrepStageRow]
    let wallSeconds: Double
    let trackCount: Int

    func write(to url: URL, alsoPrinting: Bool) {
        let text = render()
        try? text.write(to: url, atomically: true, encoding: .utf8)
        if alsoPrinting { print(text) }
    }

    private func render() -> String {
        let totals = rows.filter { $0.stage == PrepStage.trackTotal }
        let audioSeconds = totals.reduce(0) { $0 + $1.audioSeconds }
        let trackWall = totals.reduce(0) { $0 + $1.wallMs } / 1000
        let perTrack = wallSeconds / Double(max(trackCount, 1))
        let perAudioSecond = audioSeconds > 0 ? wallSeconds / audioSeconds : 0
        let totalShare = wallSeconds > 0 ? trackWall / wallSeconds * 100 : 0

        var out = "tracks                 \(trackCount)\n"
        out += String(format: "audio decoded          %.1f s (%.1f min)\n", audioSeconds, audioSeconds / 60)
        out += String(format: "wall clock             %.1f s\n", wallSeconds)
        out += String(format: "per track              %.1f s\n", perTrack)
        out += String(format: "per second of audio    %.3f s\n", perAudioSecond)
        out += String(format: "sum of TRACK_TOTAL     %.1f s (%.0f%% of wall)\n", trackWall, totalShare)
        out += "\nstage                     wall_s   share   cores   ms/audio_s\n"

        let stages = stageTotals(audioSeconds: audioSeconds)
        let stageWall = stages.reduce(0) { $0 + $1.wallSeconds }
        for stage in stages.sorted(by: { $0.wallSeconds > $1.wallSeconds }) {
            let share = stageWall > 0 ? stage.wallSeconds / stageWall * 100 : 0
            let numbers = String(
                format: " %7.1f  %5.1f%%  %6.2f  %10.1f\n",
                stage.wallSeconds,
                share,
                stage.cores,
                stage.msPerAudioSecond)
            out += pad(stage.name) + numbers
        }
        out += pad("SUM OF STAGES") + String(format: " %7.1f\n", stageWall)
        if trackWall > 0 {
            let remainder = trackWall - stageWall
            out += String(
                format: "unattributed remainder   %7.1f s (%.1f%% of per-track wall)\n",
                remainder,
                remainder / trackWall * 100)
        }
        return out
    }

    /// One row of the stage table. A named type rather than a tuple so the four
    /// numbers cannot be swapped at a call site.
    private struct StageTotal {
        let name: String
        let wallSeconds: Double
        let cores: Double
        let msPerAudioSecond: Double
    }

    private func stageTotals(audioSeconds: Double) -> [StageTotal] {
        stageOrder.compactMap { stage in
            let matching = rows.filter { $0.stage == stage }
            guard !matching.isEmpty else { return nil }
            let wall = matching.reduce(0) { $0 + $1.wallMs } / 1000
            let cpu = matching.reduce(0) { $0 + $1.cpuMs } / 1000
            return StageTotal(
                name: stage,
                wallSeconds: wall,
                cores: wall > 0 ? cpu / wall : 0,
                msPerAudioSecond: audioSeconds > 0 ? wall * 1000 / audioSeconds : 0)
        }
    }

    private func pad(_ text: String, to width: Int = 24) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private var stageOrder: [String] {
        [
            PrepStage.contentHash, PrepStage.cacheProbe, PrepStage.metadata, PrepStage.decode,
            PrepStage.loudness, PrepStage.stemSeparation, PrepStage.stemWarmup, PrepStage.mir,
            PrepStage.beatGrid, PrepStage.gridOnsetCalibration, PrepStage.instrumentFamily,
            PrepStage.stemSeries, PrepStage.cacheWrite,
        ]
    }
}
