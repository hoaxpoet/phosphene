// TapArtifacts — on-disk shapes for GT.2 tap capture.
//
// Two artifacts, both committed (they are small JSON, not audio):
//   • TapPass          — one annotation pass (beats OR downbeats) over one track.
//   • CalibrationResult — the latency round; its median offset is subtracted from
//     every subsequent tap so the recorded times sit on the audio timeline rather
//     than on Matt's reaction time.
//
// Ground truth is only ever produced by this pipeline + reconciliation — never
// hand-edited (see the `beatbench` skill, §Ground-truth maintenance).

import Foundation

// MARK: - Tap pass

struct TapPass: Codable {
    let trackID: String
    let pass: String
    let audioFile: String
    let capturedAt: String
    let latencyOffsetMs: Double
    let tapCount: Int
    /// Tap positions in seconds on the audio timeline, latency-corrected, ascending.
    let tapsS: [Double]

    enum CodingKeys: String, CodingKey {
        case trackID = "track_id"
        case pass
        case audioFile = "audio_file"
        case capturedAt = "captured_at"
        case latencyOffsetMs = "latency_offset_ms"
        case tapCount = "tap_count"
        case tapsS = "taps_s"
    }
}

// MARK: - Calibration

/// One calibration round: a single metronome pass.
struct CalibrationRound: Codable {
    let calibratedAt: String
    let bpm: Double
    let clickCount: Int
    let tapCount: Int
    let medianOffsetMs: Double
    let madMs: Double
    let offsetsMs: [Double]

    enum CodingKeys: String, CodingKey {
        case calibratedAt = "calibrated_at"
        case bpm
        case clickCount = "click_count"
        case tapCount = "tap_count"
        case medianOffsetMs = "median_offset_ms"
        case madMs = "mad_ms"
        case offsetsMs = "offsets_ms"
    }
}

/// Pooled calibration across rounds.
///
/// Measured 2026-07-27: two rounds by the same tapper, minutes apart, differed by
/// 29.5 ms (−41.6 vs −12.1) while each was internally tight (MAD 12.1 / 10.1). The
/// between-round spread is therefore several times the within-round spread, so a
/// single round understates the uncertainty and would bias every corrected tap by
/// its own drift. `medianOffsetMs` pools all rounds' offsets;
/// `betweenRoundSpreadMs` reports the disagreement so it can be judged rather than
/// hidden.
struct CalibrationResult: Codable {
    let calibratedAt: String
    let roundCount: Int
    /// Pooled median tap-minus-click offset. Subtract from raw taps.
    let medianOffsetMs: Double
    /// Pooled median absolute deviation.
    let madMs: Double
    /// Max − min of the per-round medians. Large values mean unstable calibration.
    let betweenRoundSpreadMs: Double
    let rounds: [CalibrationRound]

    enum CodingKeys: String, CodingKey {
        case calibratedAt = "calibrated_at"
        case roundCount = "round_count"
        case medianOffsetMs = "median_offset_ms"
        case madMs = "mad_ms"
        case betweenRoundSpreadMs = "between_round_spread_ms"
        case rounds
    }

    /// Rebuild the pooled summary from a round list.
    static func pooled(rounds: [CalibrationRound]) -> CalibrationResult {
        let allOffsets = rounds.flatMap(\.offsetsMs)
        let roundMedians = rounds.map(\.medianOffsetMs)
        let spread = (roundMedians.max() ?? 0) - (roundMedians.min() ?? 0)
        return CalibrationResult(
            calibratedAt: rounds.last?.calibratedAt ?? "",
            roundCount: rounds.count,
            medianOffsetMs: TapStats.median(allOffsets),
            madMs: TapStats.medianAbsoluteDeviation(allOffsets),
            betweenRoundSpreadMs: spread,
            rounds: rounds
        )
    }
}

// MARK: - Manifest lookup

/// Minimal view of the committed BeatBench manifest — just enough to resolve
/// `--track <id>` to its audio filename.
struct FixtureManifest: Decodable {
    let tracks: [Track]

    struct Track: Decodable {
        let id: String
        let filename: String?
        let suite: Int
    }

    static func load(at url: URL) throws -> FixtureManifest {
        try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: url))
    }

    func track(id: String) -> Track? {
        tracks.first { $0.id == id }
    }
}

// MARK: - Writing

enum TapArtifactWriter {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url)
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}

// MARK: - Calibration math

enum CalibrationMath {
    /// Widest believable tap latency (audio output latency + human reaction). Real
    /// values sit around 30–200 ms; anything past this is a mis-tap, not evidence.
    static let plausibleLatencyMs = 250.0

    /// Match each tap to its nearest click and return the signed offsets in ms.
    ///
    /// Offsets outside the plausible-latency band are dropped: a missed or doubled
    /// press lands mid-way between two clicks and would otherwise drag the median,
    /// mis-correcting every capture that follows.
    ///
    /// Note the guard is a *latency* window, deliberately not "within half a click
    /// period" — on a regular click grid every tap is within half a period of some
    /// click by construction, so such a test can never reject anything.
    static func offsetsMs(
        taps: [Double],
        clicks: [Double],
        maxOffsetMs: Double = plausibleLatencyMs
    ) -> [Double] {
        guard !clicks.isEmpty else { return [] }
        var offsets: [Double] = []
        for tap in taps {
            guard let nearest = clicks.min(by: { abs($0 - tap) < abs($1 - tap) }) else { continue }
            let deltaMs = (tap - nearest) * 1000.0
            if abs(deltaMs) <= maxOffsetMs { offsets.append(deltaMs) }
        }
        return offsets
    }

    /// Apply a latency offset to raw taps: shift onto the audio timeline, drop
    /// anything that lands before zero, and sort.
    static func correct(taps: [Double], latencyMs: Double) -> [Double] {
        taps.map { $0 - latencyMs / 1000.0 }.filter { $0 >= 0 }.sorted()
    }
}

// MARK: - Stats

enum TapStats {
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Median absolute deviation — robust spread, unaffected by a few wild taps.
    static func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let med = median(values)
        return median(values.map { abs($0 - med) })
    }
}
