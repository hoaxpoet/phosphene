// SessionArtifacts — Parse a Phosphene session directory for cold-start verification.
//
// Reads features.csv (per-frame beat-sync columns) and session.log (track-change
// + BeatGrid-install events), and segments the frame stream into per-track runs.
//
// Per-track segmentation key (verified against VisualizerEngine+Capture.swift:154):
// `mir.reset()` fires on every track change, zeroing MIRPipeline.elapsedSeconds.
// `playback_time_s` in features.csv == Float(mir.elapsedSeconds), so it resets
// toward ~0 at each track boundary. A boundary is any frame whose playback_time_s
// drops by more than `boundaryDropThresholdS` from the previous frame.

import Foundation

// MARK: - Frame + track model

/// One features.csv row — the columns CS.1 cares about.
struct FeatureFrame {
    let frame: Int
    let wallclockS: Double
    let playbackTimeS: Double
    let beatPhase01: Double
    let subBass: Double
    let beatBass: Double
    let bassAttRel: Double
    let gridBPM: Double
    let driftMs: Double
    let lockState: Int    // 0 unlocked, 1 locking, 2 locked
    let sessionMode: Int  // 0 reactive, 1 unlocked-grid, 2 locking-grid, 3 locked-grid
    let beatsPerBar: Int
}

/// A contiguous run of frames belonging to one track (playback_time_s monotonic).
struct TrackSegment {
    let index: Int
    let frames: [FeatureFrame]
    let title: String?
    let artist: String?
    let installedBPM: Double?
    let installedMeter: Int?

    /// Track-relative playback time of the first recorded frame.
    var firstPlaybackTimeS: Double { frames.first?.playbackTimeS ?? 0 }
    /// Track-relative playback time of the last recorded frame.
    var lastPlaybackTimeS: Double { frames.last?.playbackTimeS ?? 0 }
    /// Whether a beat grid was installed (vs reactive mode — no grid to verify).
    var hasGrid: Bool { frames.contains { $0.sessionMode != 0 } }

    var label: String {
        if let title { return artist.map { "\(title) — \($0)" } ?? title }
        return "track \(index + 1)"
    }
}

/// A "BeatGrid installed:" line from session.log.
struct LogGridEvent {
    let title: String
    let bpm: Double
    let meter: Int
}

/// A "track →" line from session.log, with its wall-clock timestamp.
struct LogTrackEvent {
    /// CFAbsoluteTime — the same epoch as features.csv `wallclock_s`.
    let timeS: Double
    let title: String
    let artist: String
}

/// Everything parsed from a session directory.
struct SessionArtifacts {
    let directory: URL
    let frames: [FeatureFrame]
    let tracks: [TrackSegment]

    /// Track boundary when playback_time_s drops by more than this (s). A real
    /// track change resets elapsedSeconds from many seconds back to ~0; within a
    /// track it only increases. 1 s is unambiguous.
    static let boundaryDropThresholdS = 1.0

    /// A frame run starting more than this many seconds before the first
    /// "track →" log event is pre-playback (preparation) and is not a track.
    static let preRollToleranceS = 8.0

    static func load(directory: URL) throws -> SessionArtifacts {
        let featuresURL = directory.appendingPathComponent("features.csv")
        guard FileManager.default.fileExists(atPath: featuresURL.path) else {
            throw VerifierError.missingFile(featuresURL)
        }
        let frames = try parseFeatures(featuresURL)
        guard !frames.isEmpty else { throw VerifierError.emptyFeatures }

        let logURL = directory.appendingPathComponent("session.log")
        let log = (try? String(contentsOf: logURL, encoding: .utf8)).map(parseLog) ?? LogEvents()

        let tracks = segment(frames: frames, log: log)
        return SessionArtifacts(directory: directory, frames: frames, tracks: tracks)
    }

    // MARK: - features.csv

    private static func parseFeatures(_ url: URL) throws -> [FeatureFrame] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { throw VerifierError.emptyFeatures }
        let columns = header.split(separator: ",").map(String.init)
        var indexOf: [String: Int] = [:]
        for (col, name) in columns.enumerated() { indexOf[name] = col }

        func col(_ name: String) throws -> Int {
            guard let idx = indexOf[name] else { throw VerifierError.missingColumn(name) }
            return idx
        }
        let iFrame = try col("frame")
        let iWall = try col("wallclock_s")
        let iPt = try col("playback_time_s")
        let iPhase = try col("beatPhase01")
        let iSub = try col("subBass")
        let iBeatBass = try col("beatBass")
        let iAtt = try col("bassAttRel")
        let iBpm = try col("grid_bpm")
        let iDrift = try col("drift_ms")
        let iLock = try col("lock_state")
        let iMode = try col("beat_sync_mode")
        let iBpb = try col("beatsPerBar")

        var frames: [FeatureFrame] = []
        frames.reserveCapacity(lines.count - 1)
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= columns.count else { continue }
            frames.append(FeatureFrame(
                frame: Int(fields[iFrame]) ?? 0,
                wallclockS: Double(fields[iWall]) ?? 0,
                playbackTimeS: Double(fields[iPt]) ?? 0,
                beatPhase01: Double(fields[iPhase]) ?? 0,
                subBass: Double(fields[iSub]) ?? 0,
                beatBass: Double(fields[iBeatBass]) ?? 0,
                bassAttRel: Double(fields[iAtt]) ?? 0,
                gridBPM: Double(fields[iBpm]) ?? 0,
                driftMs: Double(fields[iDrift]) ?? 0,
                lockState: Int(fields[iLock]) ?? 0,
                sessionMode: Int(fields[iMode]) ?? 0,
                beatsPerBar: Int(fields[iBpb]) ?? 1))
        }
        return frames
    }

    // MARK: - session.log

    private struct LogEvents {
        var tracks: [LogTrackEvent] = []
        var grids: [LogGridEvent] = []
    }

    private static func parseLog(_ text: String) -> LogEvents {
        var events = LogEvents()
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            if let range = line.range(of: "track → ") {
                let rest = String(line[range.upperBound...])
                // SessionRecorder writes "track → <title> — <artist>".
                let title: String
                let artist: String
                if let dash = rest.range(of: " — ") {
                    title = String(rest[..<dash.lowerBound])
                    artist = String(rest[dash.upperBound...])
                } else {
                    title = rest
                    artist = ""
                }
                events.tracks.append(LogTrackEvent(
                    timeS: lineTimestamp(line) ?? 0,
                    title: title,
                    artist: artist))
            } else if line.contains("BeatGrid installed:") {
                let title = capture(line, between: "track='", and: "'") ?? ""
                let bpm = capture(line, between: "bpm=", and: ",").flatMap(Double.init)
                let meter = capture(line, between: "meter=", and: "/X")
                events.grids.append(LogGridEvent(
                    title: title,
                    bpm: bpm ?? 0,
                    meter: meter.flatMap(Int.init) ?? 0))
            }
        }
        return events
    }

    /// Parse the leading `[ISO8601]` timestamp of a session.log line into a
    /// CFAbsoluteTime (`Date.timeIntervalSinceReferenceDate` — the epoch
    /// features.csv `wallclock_s` also uses). nil when the line has no timestamp.
    private static func lineTimestamp(_ line: String) -> Double? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let iso = String(line[line.index(after: line.startIndex)..<close])
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.timeIntervalSinceReferenceDate
    }

    /// Substring between two delimiters, or nil if either is absent.
    private static func capture(_ source: String, between lhs: String, and rhs: String) -> String? {
        guard let leftRange = source.range(of: lhs) else { return nil }
        let tail = source[leftRange.upperBound...]
        guard let rightRange = tail.range(of: rhs) else { return nil }
        return String(tail[..<rightRange.lowerBound])
    }

    // MARK: - Track segmentation

    private static func segment(frames: [FeatureFrame], log: LogEvents) -> [TrackSegment] {
        var runs: [[FeatureFrame]] = []
        var current: [FeatureFrame] = []
        var prevPt = -Double.infinity
        for frame in frames {
            if frame.playbackTimeS < prevPt - boundaryDropThresholdS, !current.isEmpty {
                runs.append(current)
                current = []
            }
            current.append(frame)
            prevPt = frame.playbackTimeS
        }
        if !current.isEmpty { runs.append(current) }

        // Drop pre-playback runs — those starting before the first "track →"
        // event (preparation idles the render loop before the user presses
        // play). The remaining runs map 1:1 to track events in order: a track
        // never resets MIRPipeline mid-playback, so one run per track. Without
        // this, a leading prep run shifts every track label by one.
        let events = log.tracks
        let trackRuns: [[FeatureFrame]]
        if let firstEvent = events.first {
            trackRuns = runs.filter {
                ($0.first?.wallclockS ?? 0) >= firstEvent.timeS - preRollToleranceS
            }
        } else {
            trackRuns = runs   // no log events (reactive session) — positional
        }

        return trackRuns.enumerated().map { idx, run in
            let event = idx < events.count ? events[idx] : nil
            var bpm: Double?
            var meter: Int?
            if let title = event?.title,
               let grid = log.grids.first(where: { $0.title == title }) {
                bpm = grid.bpm > 0 ? grid.bpm : nil
                meter = grid.meter > 0 ? grid.meter : nil
            }
            return TrackSegment(
                index: idx,
                frames: run,
                title: event?.title,
                artist: event.flatMap { $0.artist.isEmpty ? nil : $0.artist },
                installedBPM: bpm,
                installedMeter: meter)
        }
    }
}
