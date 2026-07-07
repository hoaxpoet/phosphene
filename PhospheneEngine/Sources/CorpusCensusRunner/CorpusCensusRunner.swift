// CorpusCensusRunner — batch corpus-analysis harness (Phase CENSUS, CENSUS.2).
// STATUS: retained-diagnostic — standalone CLI (executableTarget), run ad hoc on
//   Matt's local corpus. Zero production importers BY DESIGN; not dead. See
//   docs/AUDIT_KEEPLIST.md. Background: docs/research/CORPUS_ML_OPPORTUNITIES.md §4/§5/§8.
//
// Walks a stratified manifest of Matt's ~28k-track archive through the EXISTING
// analysis pipeline (no new ML) and emits one CSV row per track: full-mix Beat
// This! grid, drums-stem grid, the continuous octave-folded BPM disagreement
// (D-154's evidence, not just its boolean), the MoodClassifier's 10 input
// features (means, pre-normalization) + valence/arousal, K-S key + correlations,
// and the MIR tempo estimate. The census MEASURES; it changes no production
// constant (EP §Phase CENSUS scope guard).
//
// Usage:
//   .build/release/CorpusCensusRunner \
//     --root "/Volumes/Extreme SSD" \
//     --manifest tools/data/corpus_pilot_1000.csv \
//     --out "/Volumes/Extreme SSD/phosphene_census/pilot_results.csv" \
//     [--limit N] [--dual-rate] [--window-seconds 30]

import ArgumentParser
import Foundation
import Metal
import DSP
import ML
import Session

@main
struct CorpusCensusRunnerCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "CorpusCensusRunner",
        abstract: "Batch corpus analysis through Phosphene's existing pipeline (CENSUS.2).",
        discussion: """
        Reads a manifest (relpath column, joined against --root), decodes the first
        --window-seconds of each track at its FILE-NATIVE rate (mono). 30 s is the
        deliberate default: it is the preview-equivalent window production actually
        analyzes — parity, not laziness. Resumable: rows already present in --out are
        skipped. Failure rows go to <out-dir>/census_failures.log.
        """
    )

    @Option(name: .long, help: "Corpus root; manifest relpaths join against this.")
    var root: String

    @Option(name: .long, help: "Manifest CSV (relpath + tag_status columns).")
    var manifest: String

    @Option(name: .long, help: "Output CSV (created; append-only, resumable).")
    var out: String

    @Option(name: .long, help: "Analyze at most N manifest tracks (after resume-skip).")
    var limit: Int?

    @Flag(name: .long, help: "Also emit 44100 + 48000 Hz MIR rows (cross-path mood skew; pilot only).")
    var dualRate: Bool = false

    @Option(name: .long, help: "Seconds of audio analyzed from track start. Default 30 (preview parity).")
    var windowSeconds: Double = 30

    // MARK: - Run

    func run() throws {
        let rootURL = URL(fileURLWithPath: root)
        let outURL = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let failuresURL = outURL.deletingLastPathComponent().appendingPathComponent("census_failures.log")

        let manifestText = try String(contentsOf: URL(fileURLWithPath: manifest), encoding: .utf8)
        let allRows = try CensusManifest.okRows(fromCSV: manifestText)

        // Resume: skip relpaths already written.
        var done = Set<String>()
        if let existing = try? String(contentsOf: outURL, encoding: .utf8) {
            done = CensusResume.doneRelpaths(fromCSV: existing)
        }
        var pending = allRows.filter { !done.contains($0.relpath) }
        if let limit { pending = Array(pending.prefix(limit)) }
        logLine("[census] manifest=\(allRows.count) ok · done=\(done.count) · pending=\(pending.count)"
            + (dualRate ? " · dual-rate" : ""))

        // One model set reused across tracks (PREPPERF.2: graph reuse matters).
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CensusError("no Metal device available")
        }
        let beatGrid = try DefaultBeatGridAnalyzer(device: device)
        let separator = try StemSeparator(device: device)

        let outHandle = try openForAppend(outURL, headerIfNew: CensusCSV.row(CensusRow.header))
        defer { try? outHandle.close() }

        for (idx, mrow) in pending.enumerated() {
            let fileURL = rootURL.appendingPathComponent(mrow.relpath)
            let started = Date()
            var lines: [String] = []
            var timing = ""
            do {
                let result = try analyze(
                    relpath: mrow.relpath,
                    fileURL: fileURL,
                    beatGrid: beatGrid,
                    separator: separator
                )
                lines.append(result.row.csvLine())
                lines.append(contentsOf: result.extras.map { $0.csvLine() })
                timing = result.stages
            } catch {
                let msg = errorText(error)
                appendLine(failuresURL, "\(mrow.relpath)\t\(msg)")
                lines.append(CensusRow(relpath: mrow.relpath, error: msg).csvLine())
            }
            // One write per track (atomic for resume: all-or-nothing on kill).
            outHandle.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            try? outHandle.synchronize()

            let total = Date().timeIntervalSince(started)
            let flag = total > 5.0 ? "  ⚠︎>5s" : ""
            logLine("[census] \(idx + 1)/\(pending.count) \(mrow.relpath)  "
                + "total=\(String(format: "%.2f", total))s \(timing)\(flag)")
        }
        logLine("[census] done → \(out)")
    }

    // MARK: - Per-track analysis

    private struct TrackAnalysis {
        let row: CensusRow
        let extras: [CensusRow]
        let stages: String
    }

    private func analyze(
        relpath: String,
        fileURL: URL,
        beatGrid: DefaultBeatGridAnalyzer,
        separator: StemSeparator
    ) throws -> TrackAnalysis {
        var timer = StageTimer()
        let (samples, nativeRate) = try decodeMonoFloat32(url: fileURL)
        timer.mark("decode")
        let rate = Double(nativeRate)
        guard rate > 0 else { throw CensusError("zero sample rate") }
        let windowCount = min(samples.count, Int(windowSeconds * rate))
        guard windowCount >= 2048 else {
            throw CensusError("decoded window too short (\(windowCount) samples)")
        }
        let window = Array(samples[0..<windowCount])

        // Full-mix grid (analyzer resamples to 22050 internally).
        let grid = beatGrid.analyzeBeatGrid(samples: window, sampleRate: rate)
        timer.mark("grid")

        // Drums grid: separate first ~10 s → drums stem → same Beat This! path.
        let drumsGrid = try drumsGridFor(
            window: window,
            nativeRate: nativeRate,
            beatGrid: beatGrid,
            separator: separator
        )
        let drumsBPM: Double? = drumsGrid.bpm > 0 ? drumsGrid.bpm : nil
        timer.mark("drums")

        // Irregularity — record the continuous evidence AND the production boolean.
        let gridBPM = grid.bpm > 0 ? grid.bpm : nil
        let folded = (gridBPM != nil && drumsBPM != nil)
            ? foldedBPMDisagreement(grid.bpm, drumsGrid.bpm)
            : nil
        let irregular = assessBeatIrregularity(
            gridBPM: grid.bpm,
            drumsBPM: drumsGrid.bpm,
            barConfidence: grid.barConfidence
        )

        // MIR + mood at native rate.
        let mir = runMIR(samples: window, sampleRate: rate)
        timer.mark("mir")

        let row = CensusRow(
            relpath: relpath,
            durationS: Double(samples.count) / rate,
            nativeRate: rate,
            windowS: Double(windowCount) / rate,
            gridBPM: gridBPM,
            gridBeatCount: grid.beats.count,
            barConfidence: Double(grid.barConfidence),
            drumsBPM: drumsBPM,
            foldedDisagreement: folded,
            beatIrregular: irregular,
            mirBPM: mir.bpm,
            valence: mir.valence,
            arousal: mir.arousal,
            feats: mir.feats,
            keyClass: mir.keyClass,
            keyMajorR: mir.majorR,
            keyMinorR: mir.minorR
        )

        // Dual-rate: re-run only the MIR/mood step at 44100 + 48000, one extra row each.
        var extras: [CensusRow] = []
        if dualRate {
            extras = dualRateRows(relpath: relpath, window: window, rate: rate)
            timer.mark("dual")
        }
        return TrackAnalysis(row: row, extras: extras, stages: timer.summary())
    }

    /// Separate the window's first ~10 s, take the drums stem BY VALUE from
    /// stemWaveforms (CLEAN.1.2/BUG-031: never the separator's shared buffers;
    /// index 1 = drums in [vocals, drums, bass, other]), and run the same Beat
    /// This! path on it.
    private func drumsGridFor(
        window: [Float],
        nativeRate: Float,
        beatGrid: DefaultBeatGridAnalyzer,
        separator: StemSeparator
    ) throws -> BeatGrid {
        let stemCount = min(window.count, StemSeparator.requiredMonoSamples)
        let stemResult = try separator.separate(
            audio: Array(window[0..<stemCount]),
            channelCount: 1,
            sampleRate: nativeRate
        )
        let drums = Array(stemResult.stemWaveforms[1].prefix(stemResult.sampleCount))
        return beatGrid.analyzeBeatGrid(
            samples: drums,
            sampleRate: Double(StemSeparator.modelSampleRate)
        )
    }

    /// Re-run only the MIR/mood step at 44100 + 48000 Hz (cross-path mood-skew
    /// calibration): resample the SAME window, one extra row per rate.
    private func dualRateRows(relpath: String, window: [Float], rate: Double) -> [CensusRow] {
        [44100.0, 48000.0].map { target in
            let resampled = resampleMono(window, from: rate, to: target)
            return CensusRow.mirOnly(
                relpath: "\(relpath)#\(Int(target))",
                nativeRate: target,
                windowS: Double(resampled.count) / target,
                mir: runMIR(samples: resampled, sampleRate: target)
            )
        }
    }

    // MARK: - Output plumbing

    private func openForAppend(_ url: URL, headerIfNew: String) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data((headerIfNew + "\n").utf8).write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        return handle
    }

    private func appendLine(_ url: URL, _ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func errorText(_ error: Error) -> String {
        let raw = "\(error)"
        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private func logLine(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
