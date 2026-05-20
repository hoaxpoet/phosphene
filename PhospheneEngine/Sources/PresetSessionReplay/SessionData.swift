// SessionData.swift — Parse a Phosphene session directory's CSV artifacts.
//
// A session directory written by `SessionRecorder` contains:
//   features.csv  — one row per rendered frame, FeatureVector columns
//   stems.csv     — one row per analyzed frame, StemFeatures columns
//   raw_tap.wav   — captured audio
//   video.mp4     — rendered output
//   session.log   — diagnostic text
//
// This module parses features.csv + stems.csv into in-memory structs the
// replay tooling can iterate over. The parsers are tolerant of extra columns
// (forward-compat with future engine additions) but strict on the named
// columns SR.1 cares about. Missing columns raise a descriptive error.
//
// SR.1 (2026-05-20) — initial revision. Aurora Veil-specific consumers in
// AuroraVeilRoutes.swift; the parser itself is preset-agnostic.

import Foundation

// swiftlint:disable identifier_name
// CSV parsing helpers use short local names (s, v, f) for row dictionaries
// and parsed values — same pattern as Shared/AudioFeatures+Analyzed.swift.

/// One frame's worth of session data — the columns SR.1's analyses care about.
///
/// This struct is intentionally narrow (a subset of FeatureVector + StemFeatures
/// columns). Additional columns can be wired through as new analyses need them.
public struct SessionFrame: Sendable {
    public let frame: Int
    public let wallclockSeconds: Double
    public let audioTimeSeconds: Float
    public let deltaTime: Float

    // FeatureVector subset
    public let bassDev: Float
    public let bassAttRel: Float
    public let beatPhase01: Float
    public let valence: Float
    public let arousal: Float

    // StemFeatures subset
    public let drumsEnergy: Float
    public let drumsEnergyDev: Float
    public let bassEnergy: Float
    public let bassEnergyDev: Float
    public let vocalsEnergy: Float
    public let vocalsEnergyDev: Float
    public let otherEnergy: Float
    public let otherEnergyDev: Float
    public let vocalsPitchHz: Float
    public let vocalsPitchConfidence: Float

    /// Total stem energy — used by D-019 stem-warmup blend in shaders.
    public var totalStemEnergy: Float {
        vocalsEnergy + drumsEnergy + bassEnergy + otherEnergy
    }
}

/// Parsed session artifacts for one recording.
public struct SessionData: Sendable {
    public let path: URL
    public let frames: [SessionFrame]
    public let videoURL: URL?

    /// Sampling rate (frames per second) inferred from wallclock timestamps.
    public var inferredFPS: Double {
        guard let first = frames.first, let last = frames.last, frames.count >= 2 else { return 0 }
        let span = last.wallclockSeconds - first.wallclockSeconds
        guard span > 0 else { return 0 }
        return Double(frames.count - 1) / span
    }

    /// Total recorded duration (wallclock seconds).
    public var durationSeconds: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return last.wallclockSeconds - first.wallclockSeconds
    }
}

// MARK: - Parsing

public enum SessionDataError: Error, CustomStringConvertible {
    case missingFile(URL)
    case missingColumn(String, in: String)
    case rowCountMismatch(features: Int, stems: Int)
    case parseFailure(file: String, line: Int, detail: String)

    public var description: String {
        switch self {
        case .missingFile(let url):
            return "Missing required file: \(url.path)"
        case .missingColumn(let name, let file):
            return "Required column '\(name)' missing from \(file)"
        case .rowCountMismatch(let f, let s):
            return "features.csv has \(f) rows; stems.csv has \(s) rows — schemas must align"
        case .parseFailure(let file, let line, let detail):
            return "Parse failure at \(file):\(line) — \(detail)"
        }
    }
}

public enum SessionDataLoader {

    /// Load a session directory's features.csv + stems.csv into a SessionData.
    ///
    /// - Parameter directory: path to the session directory (e.g., the
    ///   2026-05-20T01-23-03Z directory).
    /// - Throws: SessionDataError on any structural problem (missing files,
    ///   missing columns, row count mismatch).
    public static func load(directory: URL) throws -> SessionData {
        let featuresURL = directory.appendingPathComponent("features.csv")
        let stemsURL = directory.appendingPathComponent("stems.csv")
        let videoURL = directory.appendingPathComponent("video.mp4")

        guard FileManager.default.fileExists(atPath: featuresURL.path) else {
            throw SessionDataError.missingFile(featuresURL)
        }
        guard FileManager.default.fileExists(atPath: stemsURL.path) else {
            throw SessionDataError.missingFile(stemsURL)
        }

        let featuresRows = try parseCSV(featuresURL, label: "features.csv")
        let stemsRows = try parseCSV(stemsURL, label: "stems.csv")

        guard featuresRows.count == stemsRows.count else {
            throw SessionDataError.rowCountMismatch(
                features: featuresRows.count, stems: stemsRows.count)
        }

        var frames: [SessionFrame] = []
        frames.reserveCapacity(featuresRows.count)
        for (f, s) in zip(featuresRows, stemsRows) {
            let frame = SessionFrame(
                frame: try intColumn(f, "frame", file: "features.csv"),
                wallclockSeconds: try doubleColumn(f, "wallclock_s", file: "features.csv"),
                audioTimeSeconds: try floatColumn(f, "time", file: "features.csv"),
                deltaTime: try floatColumn(f, "deltaTime", file: "features.csv"),
                bassDev: try floatColumn(f, "bassDev", file: "features.csv"),
                bassAttRel: try floatColumn(f, "bassAttRel", file: "features.csv"),
                beatPhase01: try floatColumn(f, "beatPhase01", file: "features.csv"),
                valence: try floatColumn(f, "valence", file: "features.csv"),
                arousal: try floatColumn(f, "arousal", file: "features.csv"),
                drumsEnergy: try floatColumn(s, "drumsEnergy", file: "stems.csv"),
                drumsEnergyDev: try floatColumn(s, "drumsEnergyDev", file: "stems.csv"),
                bassEnergy: try floatColumn(s, "bassEnergy", file: "stems.csv"),
                bassEnergyDev: try floatColumn(s, "bassEnergyDev", file: "stems.csv"),
                vocalsEnergy: try floatColumn(s, "vocalsEnergy", file: "stems.csv"),
                vocalsEnergyDev: try floatColumn(s, "vocalsEnergyDev", file: "stems.csv"),
                otherEnergy: try floatColumn(s, "otherEnergy", file: "stems.csv"),
                otherEnergyDev: try floatColumn(s, "otherEnergyDev", file: "stems.csv"),
                vocalsPitchHz: try floatColumn(s, "vocalsPitchHz", file: "stems.csv"),
                vocalsPitchConfidence: try floatColumn(s, "vocalsPitchConfidence", file: "stems.csv")
            )
            frames.append(frame)
        }

        return SessionData(
            path: directory,
            frames: frames,
            videoURL: FileManager.default.fileExists(atPath: videoURL.path) ? videoURL : nil
        )
    }

    // MARK: - Internal CSV utilities

    /// Parsed CSV: ordered list of (column-name-keyed) row dictionaries.
    fileprivate typealias Row = [String: String]

    fileprivate static func parseCSV(_ url: URL, label: String) throws -> [Row] {
        let text = try String(contentsOf: url, encoding: .utf8)
        // Split on \n; skip trailing empty.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let header = lines.first else {
            throw SessionDataError.parseFailure(file: label, line: 0, detail: "empty file")
        }
        let columns = header.split(separator: ",").map(String.init)
        var rows: [Row] = []
        rows.reserveCapacity(lines.count - 1)
        for (idx, line) in lines.dropFirst().enumerated() {
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count == columns.count else {
                throw SessionDataError.parseFailure(
                    file: label,
                    line: idx + 2,
                    detail: "got \(values.count) fields; header has \(columns.count)")
            }
            var row: Row = [:]
            for (col, val) in zip(columns, values) { row[col] = val }
            rows.append(row)
        }
        return rows
    }

    fileprivate static func floatColumn(_ row: Row, _ name: String, file: String) throws -> Float {
        guard let s = row[name] else { throw SessionDataError.missingColumn(name, in: file) }
        guard let v = Float(s) else {
            throw SessionDataError.parseFailure(file: file, line: 0, detail: "column '\(name)' = '\(s)' not Float")
        }
        return v
    }

    fileprivate static func doubleColumn(_ row: Row, _ name: String, file: String) throws -> Double {
        guard let s = row[name] else { throw SessionDataError.missingColumn(name, in: file) }
        guard let v = Double(s) else {
            throw SessionDataError.parseFailure(file: file, line: 0, detail: "column '\(name)' = '\(s)' not Double")
        }
        return v
    }

    fileprivate static func intColumn(_ row: Row, _ name: String, file: String) throws -> Int {
        guard let s = row[name] else { throw SessionDataError.missingColumn(name, in: file) }
        guard let v = Int(s) else {
            throw SessionDataError.parseFailure(file: file, line: 0, detail: "column '\(name)' = '\(s)' not Int")
        }
        return v
    }
}

// swiftlint:enable identifier_name
