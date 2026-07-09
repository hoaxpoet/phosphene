// TonalDumper — TONAL.2 (D-178) diagnostic surface for the Tonal Interval Vector.
// STATUS: retained-diagnostic — standalone CLI (executableTarget), run ad hoc on a
//   clip to eyeball the tonal signals, or over the CENSUS stratified pilot manifest
//   to MEASURE real distributions and set TonalAnalyzer's drive constants from
//   percentiles (the IFC.6 discipline), not guesses. Zero production importers BY
//   DESIGN (like InstrumentFamilyDumper); the production path is
//   MIRPipeline.tonalAnalyzer. See docs/AUDIT_KEEPLIST.md + docs/TONAL_ANALYSIS_SCOPING.md.
//
// Runs the PRODUCTION path: decode → 1024-pt FFT / 512-hop (2× overlap, the live
// ~94 Hz cadence so flux/tension calibration transfers) → MIRPipeline (whose
// ChromaExtractor + TonalAnalyzer are the shipping code) → per-frame tonal signals.
//
// File named Dumper.swift (not main.swift) to avoid Swift script-mode parsing.

import ArgumentParser
import Audio
import AVFoundation
import DSP
import Foundation

// MARK: - Per-file tonal frames

/// Per-frame tonal signals for one decoded file.
struct TonalFrames {
    var fifths: [Double] = []       // radians
    var thirds: [Double] = []       // radians
    var consonance: [Double] = []
    var tension: [Double] = []
    var flux: [Double] = []
    var fps: Double = 0
    var isEmpty: Bool { consonance.isEmpty }
}

// MARK: - JSON output

/// Percentile block for one signal (keys are p×100: 1,5,10,25,50,75,90,99).
struct SignalPercentiles: Codable {
    let p1, p5, p10, p25, p50, p75, p90, p99: Double
    init(_ values: [Double]) {
        let pct = TonalStats.percentiles(values)
        p1 = pct[1] ?? 0; p5 = pct[5] ?? 0; p10 = pct[10] ?? 0; p25 = pct[25] ?? 0
        p50 = pct[50] ?? 0; p75 = pct[75] ?? 0; p90 = pct[90] ?? 0; p99 = pct[99] ?? 0
    }
}

/// The calibration deliverable: corpus-wide + per-genre distributions.
struct CalibrationReport: Codable {
    let tracksAnalyzed: Int
    let framesTotal: Int
    let consonance: SignalPercentiles
    let tension: SignalPercentiles
    let flux: SignalPercentiles
    let genreMedianConsonance: [String: Double]
    let genreMedianTension: [String: Double]
}

// MARK: - Command

@main
struct TonalDumperCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "TonalDumper",
        abstract: "Dump / calibrate the Tonal Interval Vector signals (fifths phase, consonance, tension, flux)."
    )

    @Option(name: .long, help: "Single audio file (m4a / wav / mp3 / flac).")
    var audio: String?

    @Option(name: .long, help: "Batch: a CSV manifest with a `relpath` column (e.g. corpus_pilot_1000.csv).")
    var manifest: String?

    @Option(name: .long, help: "Batch: directory prefixed to each manifest relpath (the corpus root).")
    var root: String?

    @Option(name: .long, help: "Batch: cap the number of tracks analysed.")
    var limit: Int?

    @Option(name: .long, help: "Batch: analyse the first N seconds per track (default 30 = preview parity).")
    var clipSeconds: Double = 30

    @Option(name: .long, help: "Single-file: start offset seconds (default 0).")
    var start: Double = 0

    @Option(name: .long, help: "Single-file: duration seconds (default: whole file).")
    var duration: Double?

    @Option(name: .long, help: "Single-file: table window seconds (default 1.0).")
    var window: Double = 1.0

    @Option(name: .long, help: "JSON output path (single-file: per-window series; batch: calibration report).")
    var out: String?

    func run() throws {
        if let manifest {
            try runBatch(manifestPath: manifest)
        } else if let audio {
            try runSingle(path: audio)
        } else {
            throw ValidationError("provide --audio <file> or --manifest <csv> --root <dir>")
        }
    }

    // MARK: Single-file

    private func runSingle(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("audio file not found: \(path)")
        }
        FileHandle.standardError.write(Data("[TD] decoding \(url.lastPathComponent) …\n".utf8))
        let (samples, rate) = try decodeMono(url: url, start: start, duration: duration)
        let frames = analyzeTonal(samples: samples, sampleRate: rate)
        guard !frames.isEmpty else { throw ValidationError("no analysable frames (clip too short?)") }

        printWindowTable(frames)
        printSummary(frames, label: url.lastPathComponent)

        if let out {
            let series = windowSeries(frames)
            try JSONEncoder().encode(series).write(to: URL(fileURLWithPath: out))
            FileHandle.standardError.write(Data("[TD] wrote \(out)\n".utf8))
        }
    }

    // MARK: Batch calibration

    private func runBatch(manifestPath: String) throws {
        guard let root else { throw ValidationError("--manifest requires --root <corpus dir>") }
        let rows = try readManifest(manifestPath)
        let capped = limit.map { Array(rows.prefix($0)) } ?? rows
        FileHandle.standardError.write(Data("[TD] \(capped.count) tracks from \(manifestPath)\n".utf8))

        var allCons: [Double] = [], allTens: [Double] = [], allFlux: [Double] = []
        var genreCons: [String: [Double]] = [:], genreTens: [String: [Double]] = [:]
        var analysed = 0
        print("relpath,frames,cons_p50,tens_p50,flux_p90,genre")
        for row in capped {
            let url = URL(fileURLWithPath: root).appendingPathComponent(row.relpath)
            guard FileManager.default.fileExists(atPath: url.path),
                  let decoded = try? decodeMono(url: url, start: 0, duration: clipSeconds) else {
                FileHandle.standardError.write(Data("[TD] skip (unreadable): \(row.relpath)\n".utf8))
                continue
            }
            let frames = analyzeTonal(samples: decoded.samples, sampleRate: decoded.sampleRate)
            guard !frames.isEmpty else { continue }
            analysed += 1
            allCons += frames.consonance; allTens += frames.tension; allFlux += frames.flux
            genreCons[row.genre, default: []].append(TonalStats.median(frames.consonance))
            genreTens[row.genre, default: []].append(TonalStats.median(frames.tension))
            let line = "\(csvSafe(row.relpath)),\(frames.consonance.count),"
                + fmt(TonalStats.median(frames.consonance)) + ","
                + fmt(TonalStats.median(frames.tension)) + ","
                + fmt(TonalStats.percentile(frames.flux.sorted(), 0.90)) + ",\(row.genre)"
            print(line)
        }

        let report = CalibrationReport(
            tracksAnalyzed: analysed,
            framesTotal: allCons.count,
            consonance: SignalPercentiles(allCons),
            tension: SignalPercentiles(allTens),
            flux: SignalPercentiles(allFlux),
            genreMedianConsonance: genreCons.mapValues { TonalStats.median($0) },
            genreMedianTension: genreTens.mapValues { TonalStats.median($0) }
        )
        printCalibration(report)
        if let out {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(report).write(to: URL(fileURLWithPath: out))
            FileHandle.standardError.write(Data("[TD] wrote \(out)\n".utf8))
        }
    }
}
