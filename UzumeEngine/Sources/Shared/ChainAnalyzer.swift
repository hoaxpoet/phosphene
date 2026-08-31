// ChainAnalyzer — Post-session audio-chain health verdict (ASH.2).
//
// Reads a finished session directory and grades the audio chain that produced
// it: peak level from raw_tap.wav (the normalization/attenuation guard) and the
// SIGNAL_HEALTH / DRM-silence / tap-reinstall lines in session.log. When the
// session contains the Love Rehab reference track it also records the sub-bass
// onset count from features.csv — REPORTED only, never gated: that count is
// empirically AGC-invariant (D-184), a rhythm fingerprint, not a degradation
// signal (docs/ARCHITECTURE.md §Validated Onset Counts).
//
// One analyzer, two callers:
//   • VisualizerEngine runs it in-process at session end (writes chain_health.json
//     + a `CHAIN_HEALTH:` summary line into session.log).
//   • Scripts/analyze_session_chain.sh runs the SAME code out-of-process against
//     an arbitrary (including pre-ASH historical) session dir for retroactive
//     grading.
//
// It never re-derives beat phase (retired premise, Choice A 2026-05-25) — onset
// counting is rising-edge crossings of the cached `beatBass` column only.
// Missing artifacts are noted, never fatal: a pre-ASH dir with no SIGNAL_HEALTH
// lines and no raw_tap grades on whatever evidence is present.

import AVFoundation
import Foundation

// MARK: - ChainHealth

/// Machine-written chain-health verdict, serialized to `chain_health.json`.
public struct ChainHealth: Codable, Sendable, Equatable {

    /// Overall grade. `broken` = capture unusable (dead tap / pure silence);
    /// `degraded` = usable but compromised (low level, DRM gaps, weak onsets);
    /// `clean` = no degradation evidence found.
    public enum Verdict: String, Codable, Sendable {
        case clean, degraded, broken
    }

    public var verdict: Verdict
    /// Machine-readable reason tokens, e.g. `low_peak(-13.4dBFS)`, `dead_tap`,
    /// `love_rehab_onsets_low(median=3,ref=11)`. Empty when `clean`.
    public var reasons: [String]
    /// Peak level of raw_tap.wav in dBFS, or nil when the file is absent/unreadable.
    public var peakDBFS: Double?
    /// Output-device sample rate from the last SIGNAL_HEALTH line, if any.
    public var outputSampleRateHz: Int?
    /// Median sub-bass onsets per 5 s over the Love Rehab segment, if present.
    public var loveRehabMedianOnsetsPer5s: Int?
    /// Non-fatal observations (e.g. `no_raw_tap`) that did not change the verdict.
    public var notes: [String]

    public init(verdict: Verdict, reasons: [String] = [], peakDBFS: Double? = nil,
                outputSampleRateHz: Int? = nil, loveRehabMedianOnsetsPer5s: Int? = nil,
                notes: [String] = []) {
        self.verdict = verdict
        self.reasons = reasons
        self.peakDBFS = peakDBFS
        self.outputSampleRateHz = outputSampleRateHz
        self.loveRehabMedianOnsetsPer5s = loveRehabMedianOnsetsPer5s
        self.notes = notes
    }

    /// The one-line `session.log` summary: `CHAIN_HEALTH: verdict=… reasons=[…]`.
    public var logLine: String {
        "CHAIN_HEALTH: verdict=\(verdict.rawValue) reasons=[\(reasons.joined(separator: ","))]"
    }
}

// MARK: - ChainAnalyzer

/// Grades a session directory's audio chain. Pure I/O over the session artifacts;
/// no engine state, so it runs identically in-process and from the CLI.
public enum ChainAnalyzer {

    // MARK: Thresholds (RUNBOOK §"Recording the quality reel" post-recording checks)

    /// Peak dBFS at/above which the level is healthy (mirrors SignalHealthMonitor).
    public static let healthyFloorDBFS = -12.0
    /// Peak dBFS below which the level is critical (broken); between the two: low.
    public static let criticalCeilingDBFS = -15.0
    /// Sub-bass onset rising-edge threshold on the `beatBass` column. Calibrated so
    /// the real Love Rehab capture yields the validated 11 onsets/5 s across
    /// [0.05, 0.5]; 0.2 sits mid-band. (docs/ARCHITECTURE.md §Validated Onset Counts)
    public static let onsetThreshold = 0.2
    /// Love Rehab reference onsets per 5 s (docs/ARCHITECTURE.md §Validated Onset
    /// Counts). REPORTED, never gated: the onset count is empirically AGC-invariant
    /// — attenuation, dynamic compression, and hard limiting all leave it at ~11
    /// (D-184). Normalization is caught by the PEAK check, not this; the count is a
    /// rhythm-density fingerprint the reel operator can eyeball, not a verdict input.
    public static let loveRehabReferenceOnsets = 11

    // MARK: - Public API

    /// Grade `sessionDir`. Never throws — missing artifacts degrade the evidence
    /// available, not the call.
    public static func analyze(sessionDir: URL) -> ChainHealth {
        var reasons: [String] = []
        var notes: [String] = []
        var broken = false

        // 1. raw_tap.wav peak level.
        let peakDBFS = peakDBFS(rawTapURL: sessionDir.appendingPathComponent("raw_tap.wav"))
        if let peak = peakDBFS {
            if peak < criticalCeilingDBFS {
                broken = true
                reasons.append("critical_peak(\(fmt(peak))dBFS)")
            } else if peak < healthyFloorDBFS {
                reasons.append("low_peak(\(fmt(peak))dBFS)")
            }
        } else {
            notes.append("no_raw_tap")
        }

        // 2. session.log line scan.
        let log = LogScan(logURL: sessionDir.appendingPathComponent("session.log"))
        if log.deadTap {
            broken = true
            reasons.append("dead_tap")
        }
        if log.bandLowAfterHealthy { reasons.append("signal_health_band_low") }
        if log.drmSilenceLines > 0 { reasons.append("drm_silence(\(log.drmSilenceLines))") }
        if log.tapReinstalls > 0 { reasons.append("tap_reinstalls(\(log.tapReinstalls))") }

        // 3. Love Rehab onset count — REPORTED for the reel operator, not gated.
        // The count is AGC-invariant (D-184), so it can't detect normalization; it
        // is recorded as an informational rhythm-density metric only.
        var loveRehabMedian: Int?
        if isLoveRehabSession(sessionDir: sessionDir, log: log) {
            loveRehabMedian = loveRehabMedianOnsets(
                featuresURL: sessionDir.appendingPathComponent("features.csv"))
        }

        let verdict: ChainHealth.Verdict = broken ? .broken : (reasons.isEmpty ? .clean : .degraded)
        return ChainHealth(
            verdict: verdict,
            reasons: reasons,
            peakDBFS: peakDBFS,
            outputSampleRateHz: log.lastSampleRateHz,
            loveRehabMedianOnsetsPer5s: loveRehabMedian,
            notes: notes)
    }

    /// Analyze `sessionDir`, write `chain_health.json`, and append the summary
    /// line to `session.log`. Returns the verdict. Safe to call after the recorder
    /// has closed its handles (it appends).
    @discardableResult
    public static func analyzeAndWrite(sessionDir: URL) -> ChainHealth {
        let health = analyze(sessionDir: sessionDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(health) {
            try? data.write(to: sessionDir.appendingPathComponent("chain_health.json"))
        }
        let line = Data((health.logLine + "\n").utf8)
        let logURL = sessionDir.appendingPathComponent("session.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: logURL)
        }
        return health
    }

    // MARK: - raw_tap.wav peak

    /// Peak absolute sample of raw_tap.wav as dBFS, or nil if absent/unreadable.
    static func peakDBFS(rawTapURL: URL) -> Double? {
        guard FileManager.default.fileExists(atPath: rawTapURL.path),
              let file = try? AVAudioFile(forReading: rawTapURL) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return nil }
        var peak: Float = 0
        let frameLength = Int(buffer.frameLength)
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for i in 0..<frameLength { peak = max(peak, abs(samples[i])) }
        }
        return dbfs(peak: peak)
    }

    /// Linear peak → dBFS. Silence maps to −120 (matches SignalHealthMonitor).
    static func dbfs(peak: Float) -> Double {
        peak > 1e-7 ? Double(20 * log10f(peak)) : -120
    }

    // MARK: - Love Rehab onsets (features.csv `beatBass`)

    /// True when this session captured the Love Rehab reference track — detected
    /// from the session-dir name or a `track →` / provenance line in session.log.
    static func isLoveRehabSession(sessionDir: URL, log: LogScan) -> Bool {
        let dir = normalized(sessionDir.lastPathComponent)
        return dir.contains("loverehab") || log.mentionsLoveRehab
    }

    /// Median sub-bass onsets per non-overlapping 5 s window over features.csv, or
    /// nil if the file/columns are absent. Onset = rising edge of `beatBass` above
    /// `onsetThreshold`. Binned by `wallclock_s` offset from the first frame — a
    /// monotonic axis that (unlike `playback_time_s`, which resets per track)
    /// stays continuous across the whole session.
    ///
    /// ponytail: whole-file median, not per-track segmentation. Exact for a
    /// single-track capture (the reel/fixture case); for a multi-track session it
    /// is the typical onset density across the file. Isolate the Love Rehab
    /// segment only if a multi-track false-negative ever shows up.
    static func loveRehabMedianOnsets(featuresURL: URL) -> Int? {
        guard let text = try? String(contentsOf: featuresURL, encoding: .utf8) else { return nil }
        var lines = text.split(whereSeparator: \.isNewline)
        guard let header = lines.first else { return nil }
        let columns = header.split(separator: ",").map(String.init)
        guard let iBeat = columns.firstIndex(of: "beatBass"),
              let iTime = columns.firstIndex(of: "wallclock_s") else { return nil }
        lines.removeFirst()

        var onsetTimes: [Double] = []
        var prev = 0.0
        var firstTime: Double?
        var maxTime = 0.0
        for line in lines {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > max(iBeat, iTime),
                  let beat = Double(fields[iBeat]), let raw = Double(fields[iTime]) else { continue }
            let time = raw - (firstTime ?? raw)
            firstTime = firstTime ?? raw
            if prev <= onsetThreshold && beat > onsetThreshold { onsetTimes.append(time) }
            prev = beat
            maxTime = max(maxTime, time)
        }
        guard maxTime > 0 else { return nil }

        var windows: [Int] = []
        var start = 0.0
        while start < maxTime {
            windows.append(onsetTimes.filter { $0 >= start && $0 < start + 5.0 }.count)
            start += 5.0
        }
        guard !windows.isEmpty else { return nil }
        return windows.sorted()[windows.count / 2]
    }

    // MARK: - Helpers

    private static func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    /// Lowercase, strip non-alphanumerics — so "Love Rehab", "love_rehab",
    /// "fixturegen-love_rehab" all normalize to a substring-matchable form.
    private static func normalized(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - LogScan

    /// One pass over session.log, extracting every chain-health signal.
    struct LogScan {
        var deadTap = false
        /// D-197 follow-up — "degraded only after loud": a `band=low`/`band=critical`
        /// window counts as degradation ONLY if it occurs AFTER a `band=healthy`
        /// window (the chain was loud, then dropped). Low/critical windows that
        /// precede the first healthy window are a quiet song intro / capture warmup,
        /// not a degraded chain, and no longer flag the verdict. SIGNAL_HEALTH lines
        /// are chronological in session.log. (A never-loud chain is a dead-tap /
        /// silence case, covered by `deadTap` + the silence-extended path.)
        var bandLowAfterHealthy = false
        var drmSilenceLines = 0
        var tapReinstalls = 0
        var lastSampleRateHz: Int?
        var mentionsLoveRehab = false

        init(logURL: URL) {
            guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
            var sawHealthy = false
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = String(raw)
                let lower = line.lowercased()
                if lower.contains("love rehab") || lower.contains("love_rehab") {
                    mentionsLoveRehab = true
                }
                if line.contains("SIGNAL_HEALTH:") {
                    if line.contains("deadTap=true") { deadTap = true }
                    if line.contains("band=healthy") { sawHealthy = true }
                    if sawHealthy, line.contains("band=low") || line.contains("band=critical") {
                        bandLowAfterHealthy = true
                    }
                    if let range = line.range(of: "rate="),
                       let rate = Int(line[range.upperBound...]
                           .prefix { $0.isNumber }) { lastSampleRateHz = rate }
                }
                // DRM-silence catalog lines (SessionRecorder / AudioInputRouter).
                if lower.contains("drm") && lower.contains("silen") { drmSilenceLines += 1 }
                if lower.contains("tap reinstall") { tapReinstalls += 1 }
            }
        }
    }
}
