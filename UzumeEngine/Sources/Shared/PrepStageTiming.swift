// PrepStageTiming — PREP.1 per-stage preparation timing. MEASUREMENT ONLY.
//
// D-242 set a 7.5 s/track budget for session preparation and recorded that no
// per-stage timing existed for the local-file path. This is that timing: one
// row per (track, stage) with wall clock, process CPU consumed during the
// stage, and the track's decoded duration, written as a `preparation.csv`
// sidecar beside `features.csv` / `stems.csv` in the session directory.
//
// **The gate.** Nothing here runs unless `UZUME_PREP_TIMING=1` is in the
// environment. `PrepStageSink.ifEnabled(...)` returns `nil` otherwise, so a
// normal session carries `PrepStageProbe.disabled` down the call chain and
// nothing else — no timestamps taken, no rows allocated, no file opened. Call
// sites read `probe.measure(PrepStage.decode) { ... }`, which falls straight
// through to the body when the probe is disabled.
//
// **Reading `cpu_cores`.** `cpu_ms / wall_ms` — CPU-seconds burned per wall
// second, i.e. how many cores the stage held on average. ~1.0 is one saturated
// core, ~8 is eight, and « 1.0 means the process was waiting (disk, or a GPU
// command buffer). It is process-wide (`getrusage(RUSAGE_SELF)`), so it is
// only meaningful when one track is being prepared at a time; a concurrent
// run's CPU column attributes every worker's cost to whichever stage happened
// to be open. Wall clock stays correct either way.

import Foundation

// MARK: - Row

/// One measured stage of one track's preparation.
public struct PrepStageRow: Sendable {
    /// Source filename, as it appears in `session.log`.
    public let track: String
    /// Stage name — see `PrepStage` for the canonical set.
    public let stage: String
    /// Wall-clock duration of the stage.
    public let wallMs: Double
    /// Process CPU (user + system) consumed while the stage was open.
    public let cpuMs: Double
    /// Decoded duration of the track's audio, so cost can be expressed per
    /// second of audio rather than per track. `0` before the decode stage has
    /// run (hash / cache probe / metadata), where the value is not yet known.
    public let audioSeconds: Double

    public init(track: String, stage: String, wallMs: Double, cpuMs: Double, audioSeconds: Double) {
        self.track = track
        self.stage = stage
        self.wallMs = wallMs
        self.cpuMs = cpuMs
        self.audioSeconds = audioSeconds
    }

    /// Average cores held over the stage. `nil` for a zero-length stage.
    public var cpuCores: Double? {
        wallMs > 0 ? cpuMs / wallMs : nil
    }
}

// MARK: - Stage names

/// The canonical stage set, so the CSV's `stage` column is greppable and the
/// report's table rows line up run to run.
public enum PrepStage {
    public static let contentHash = "content_hash"
    public static let cacheProbe = "cache_probe"
    public static let metadata = "metadata_artwork"
    public static let decode = "decode"
    public static let loudness = "loudness_profile"
    public static let stemSeparation = "stem_separation"
    public static let stemWarmup = "stem_warmup"
    public static let mir = "mir"
    public static let beatGrid = "beat_grid"
    public static let gridOnsetCalibration = "grid_onset_calibration"
    public static let instrumentFamily = "instrument_family"
    public static let stemSeries = "stem_series_sweep"
    public static let cacheWrite = "cache_write"
    /// Whole-track wall clock, for the sum-to-within-a-few-percent check.
    public static let trackTotal = "TRACK_TOTAL"
}

// MARK: - Probe

/// Per-track handle onto a `PrepStageSink`. One value passed down the
/// preparation call chain, so a stage boundary reads
/// `probe.measure(PrepStage.decode) { ... }` and a disabled probe costs one
/// branch. `.disabled` is the production default everywhere.
public struct PrepStageProbe: Sendable {

    /// The no-op probe. Every default parameter in the pipeline is this.
    public static let disabled = PrepStageProbe(sink: nil, track: "")

    let sink: PrepStageSink?
    let track: String
    /// Decoded duration of this track, once known. Stages measured before the
    /// decode record `0` and are backfilled by `notingAudioSeconds`.
    var audioSeconds: Double

    public init(sink: PrepStageSink?, track: String, audioSeconds: Double = 0) {
        self.sink = sink
        self.track = track
        self.audioSeconds = audioSeconds
    }

    /// Whether anything is being recorded — for skipping work that exists only
    /// to be measured.
    public var isEnabled: Bool { sink != nil }

    /// Run `body`, record how long it took and how much CPU it burned.
    public func measure<T>(_ stage: String, _ body: () throws -> T) rethrows -> T {
        guard let sink else { return try body() }
        let wall0 = Date()
        let cpu0 = PrepStageSink.cpuSeconds()
        defer {
            sink.append(PrepStageRow(
                track: track,
                stage: stage,
                wallMs: Date().timeIntervalSince(wall0) * 1000,
                cpuMs: (PrepStageSink.cpuSeconds() - cpu0) * 1000,
                audioSeconds: audioSeconds
            ))
        }
        return try body()
    }

    /// `async` twin — `PreviewAudio.extractMetadata` / `extractArtwork` are the
    /// two async stages.
    public func measureAsync<T>(_ stage: String, _ body: () async throws -> T) async rethrows -> T {
        guard let sink else { return try await body() }
        let wall0 = Date()
        let cpu0 = PrepStageSink.cpuSeconds()
        defer {
            sink.append(PrepStageRow(
                track: track,
                stage: stage,
                wallMs: Date().timeIntervalSince(wall0) * 1000,
                cpuMs: (PrepStageSink.cpuSeconds() - cpu0) * 1000,
                audioSeconds: audioSeconds
            ))
        }
        return try await body()
    }

    /// Record a stage the caller timed itself (the whole-track total).
    public func record(_ stage: String, wallMs: Double, cpuMs: Double) {
        sink?.append(PrepStageRow(
            track: track,
            stage: stage,
            wallMs: wallMs,
            cpuMs: cpuMs,
            audioSeconds: audioSeconds
        ))
    }

    /// Copy of this probe that knows the track's decoded duration, and
    /// backfills it onto the stages already recorded before the decode.
    public func notingAudioSeconds(_ seconds: Double) -> PrepStageProbe {
        sink?.backfillAudioSeconds(seconds, track: track)
        return PrepStageProbe(sink: sink, track: track, audioSeconds: seconds)
    }
}

// MARK: - Sink

/// Collects `PrepStageRow`s and writes `preparation.csv`. Thread-safe: the
/// local path runs stages on a detached task and the measurement runner may
/// run several tracks at once.
public final class PrepStageSink: @unchecked Sendable {

    /// The gate. `UZUME_PREP_TIMING=1` and nothing else turns this on.
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UZUME_PREP_TIMING"] == "1"
    }

    private let lock = NSLock()
    private var rows: [PrepStageRow] = []

    /// Where `preparation.csv` is written on `flush()`.
    public let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }

    /// `nil` unless the environment gate is set — the one call every
    /// production site makes. `directory` is the session directory;
    /// `preparation.csv` lands beside `features.csv` in it.
    public static func ifEnabled(inSessionDirectory directory: URL?) -> PrepStageSink? {
        guard isEnabled, let directory else { return nil }
        return PrepStageSink(destination: directory.appendingPathComponent("preparation.csv"))
    }

    /// Record a stage that was timed by the caller (the whole-track total, or
    /// a stage whose boundaries don't fit a closure).
    public func append(_ row: PrepStageRow) {
        lock.withLock { rows.append(row) }
    }

    /// Backfill `audio_s` on rows recorded before the decode revealed the
    /// track's duration (hash, cache probe, metadata). Called once per track
    /// after the decode stage.
    public func backfillAudioSeconds(_ seconds: Double, track: String) {
        lock.withLock {
            for index in rows.indices where rows[index].track == track && rows[index].audioSeconds == 0 {
                rows[index] = PrepStageRow(
                    track: rows[index].track,
                    stage: rows[index].stage,
                    wallMs: rows[index].wallMs,
                    cpuMs: rows[index].cpuMs,
                    audioSeconds: seconds
                )
            }
        }
    }

    // MARK: Output

    /// Snapshot of everything recorded so far.
    public var snapshot: [PrepStageRow] {
        lock.withLock { rows }
    }

    /// CSV text — header plus one line per row. Separated from `flush()` so
    /// tests can assert the format without touching the filesystem.
    public var csv: String {
        var out = "track,stage,wall_ms,cpu_ms,cpu_cores,audio_s,ms_per_audio_s\n"
        for row in snapshot {
            let cores = row.cpuCores.map { String(format: "%.2f", $0) } ?? ""
            let perAudio = row.audioSeconds > 0
                ? String(format: "%.2f", row.wallMs / row.audioSeconds)
                : ""
            out += "\"\(row.track.replacingOccurrences(of: "\"", with: "\"\""))\","
                + "\(row.stage),"
                + String(format: "%.1f,%.1f,", row.wallMs, row.cpuMs)
                + "\(cores),"
                + String(format: "%.2f,", row.audioSeconds)
                + "\(perAudio)\n"
        }
        return out
    }

    /// Write `preparation.csv`. Best-effort: a measurement sidecar never fails
    /// a session.
    public func flush() {
        try? csv.write(to: destination, atomically: true, encoding: .utf8)
    }

    // MARK: Internals

    /// Process CPU (user + system) in seconds. GPU time does not appear here —
    /// a stage that waits on an MPSGraph command buffer reads as low CPU, which
    /// is exactly the distinction the `cpu_cores` column exists to make visible.
    public static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }
}
