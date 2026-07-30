// SessionReplay — score a recorded session's LIVE grid (GT.3).
//
// The offline mode scores the prep-time grid. This scores what actually reached the
// visuals: the live grid as it behaved during playback, recovered from the session's
// `features.csv`.
//
// TWO CLASSES OF NUMBER, deliberately kept apart
// ----------------------------------------------
//   • Tracker-reported drift (`drift_ms`) — the tracker's own residual against its own
//     grid. Available for EVERY track in a session and directly comparable to BUG-065's
//     evidence. But it is self-reported: a grid locked confidently to the wrong pulse
//     reports small drift. It cannot, alone, tell you the beat was right.
//   • Ground-truth phase error — live beats vs GT.2 ground truth. Only valid where the
//     fixture IS the audio that was played, i.e. tracks segmented from this same
//     session (`source: tap` + matching `source_session`). For corpus-rip fixtures the
//     streamed master is a different recording, so the timelines do not correspond and
//     scoring them would produce confident nonsense.
//
// Reporting only the first would flatter the system; reporting the second on tracks it
// does not apply to would fabricate. Both are labelled at every output.

import Foundation
import ArgumentParser

// MARK: - Session rows

struct SessionFrame {
    let wallclock: Double
    let trackElapsed: Double
    let beatPhase01: Double
    let driftMs: Double
    let lockState: Int
    let gridBPM: Double
}

struct TrackSegment {
    let frames: [SessionFrame]
    var start: Double { frames.first?.trackElapsed ?? 0 }
    var end: Double { frames.last?.trackElapsed ?? 0 }
    var duration: Double { end - start }

    /// Real elapsed wall time. A genuine play advances track position at ~1× this;
    /// a seek advances track position far faster (the 2026-07-27 session opens with
    /// 237 s of track position covered in 8.4 s of wall time — a scrub, not a play).
    var wallDuration: Double {
        (frames.last?.wallclock ?? 0) - (frames.first?.wallclock ?? 0)
    }

    /// True when track position advanced at roughly real-time speed.
    var isRealPlayback: Bool {
        guard wallDuration > 5 else { return false }
        let rate = duration / wallDuration
        return rate > 0.5 && rate < 1.5
    }

    /// Median grid BPM — the fingerprint used to identify which track this is.
    var medianGridBPM: Double {
        let values = frames.map(\.gridBPM).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return 0 }
        return values[values.count / 2]
    }

    /// Live beat times, recovered from `beatPhase01` wrapping 1 → 0.
    var liveBeats: [Double] {
        var beats: [Double] = []
        for index in 1..<max(frames.count, 1) {
            let previous = frames[index - 1].beatPhase01
            let current = frames[index].beatPhase01
            // A wrap is a large downward step; ordinary frame-to-frame motion is small.
            if previous > 0.7 && current < 0.3 {
                beats.append(frames[index].trackElapsed)
            }
        }
        return beats
    }
}

// MARK: - Live metrics

struct LiveScores {
    let trackID: String?
    let suite: Int?
    let medianGridBPM: Double
    let durationS: Double
    let frameCount: Int

    // Self-reported (every track)
    let driftP50: Double
    let driftP90: Double
    let driftP99: Double
    let driftByWindow: [(startS: Double, p90: Double)]
    let lockPercent: Double
    let timeToLockS: Double?
    let timeToUnlockS: Double?
    let confidentWrongRate: Double

    // Ground-truth anchored (tap-derived tracks only)
    let groundTruthScores: BeatScores?
    let groundTruthNote: String
}

enum SessionReplayScorer {

    /// Perceptual window used for lock / confident-wrong, matching the program's ±70 ms.
    static let perceptualWindowMs = 70.0
    /// `lock_state == 2` is the engine's own "locked" verdict.
    static let lockedState = 2

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))
        return sorted[index]
    }

    /// First moment drift enters — and stays inside — the perceptual window for a
    /// sustained run. Read alongside lock %: a track can lock instantly and lose it,
    /// which shows up as a low time-to-lock next to a poor lock percentage.
    static func firstSustainedLock(segment: TrackSegment) -> Double? {
        var runStart: Double?
        for frame in segment.frames {
            if abs(frame.driftMs) <= perceptualWindowMs {
                if runStart == nil { runStart = frame.trackElapsed }
                if let start = runStart, frame.trackElapsed - start >= 3.0 {
                    return start - segment.start
                }
            } else {
                runStart = nil
            }
        }
        return nil
    }

    /// First moment drift leaves the window and STAYS out. On a ramping track this is
    /// the number that matters: drift starts inside the window (so time-to-lock reads
    /// 0 s) and then walks out and never returns.
    static func firstSustainedUnlock(segment: TrackSegment) -> Double? {
        var runStart: Double?
        for frame in segment.frames {
            if abs(frame.driftMs) > perceptualWindowMs {
                if runStart == nil { runStart = frame.trackElapsed }
                if let start = runStart, frame.trackElapsed - start >= 5.0 {
                    return start - segment.start
                }
            } else {
                runStart = nil
            }
        }
        return nil
    }

    /// p90 |drift| per 30 s window — the BUG-065 curve. A single percentile over a whole
    /// track hides drift that grows, which is the defect's defining behaviour.
    static func driftCurve(segment: TrackSegment) -> [(startS: Double, p90: Double)] {
        var byWindow: [(startS: Double, p90: Double)] = []
        var windowStart = segment.start
        while windowStart < segment.end {
            let windowEnd = windowStart + 30
            let inWindow = segment.frames
                .filter { $0.trackElapsed >= windowStart && $0.trackElapsed < windowEnd }
                .map { abs($0.driftMs) }
            if !inWindow.isEmpty {
                byWindow.append((windowStart - segment.start, percentile(inWindow, 0.90)))
            }
            windowStart = windowEnd
        }
        return byWindow
    }

    static func score(
        segment: TrackSegment,
        trackID: String?,
        suite: Int?,
        groundTruth: [Double]?,
        groundTruthNote: String
    ) -> LiveScores {
        let absDrift = segment.frames.map { abs($0.driftMs) }
        let locked = segment.frames.filter { $0.lockState == lockedState }
        let lockPercent = segment.frames.isEmpty
            ? 0
            : Double(locked.count) / Double(segment.frames.count) * 100

        // Confident-wrong: the engine says locked, yet the residual is outside the
        // perceptual window. This is the category-5 metric and the honest-failure check.
        let confidentWrong = segment.frames.filter {
            $0.lockState == lockedState && abs($0.driftMs) > perceptualWindowMs
        }
        let confidentWrongRate = locked.isEmpty
            ? 0
            : Double(confidentWrong.count) / Double(locked.count) * 100

        let timeToLock = firstSustainedLock(segment: segment)
        let timeToUnlock = firstSustainedUnlock(segment: segment)
        let byWindow = driftCurve(segment: segment)

        // Score only over the span where BOTH exist. Ground truth often covers ~100 s of
        // a multi-minute track (Matt tapped a segment), so windowing one side only —
        // as the first implementation did — compares 100 s of truth against 400 s of
        // live beats and tanks precision for a reason that has nothing to do with the
        // grid's quality.
        var truthScores: BeatScores?
        if let groundTruth, !groundTruth.isEmpty {
            let live = segment.liveBeats
            let overlapStart = max(live.first ?? 0, groundTruth.first ?? 0)
            let overlapEnd = min(live.last ?? 0, groundTruth.last ?? 0)
            if overlapEnd - overlapStart > 20 {
                let liveWindow = live.filter { $0 >= overlapStart && $0 <= overlapEnd }
                let truthWindow = groundTruth.filter { $0 >= overlapStart && $0 <= overlapEnd }
                if liveWindow.count >= 8 && truthWindow.count >= 8 {
                    truthScores = Metrics.score(reference: truthWindow, estimate: liveWindow)
                }
            }
        }

        return LiveScores(
            trackID: trackID,
            suite: suite,
            medianGridBPM: segment.medianGridBPM,
            durationS: segment.duration,
            frameCount: segment.frames.count,
            driftP50: percentile(absDrift, 0.50),
            driftP90: percentile(absDrift, 0.90),
            driftP99: percentile(absDrift, 0.99),
            driftByWindow: byWindow,
            lockPercent: lockPercent,
            timeToLockS: timeToLock,
            timeToUnlockS: timeToUnlock,
            confidentWrongRate: confidentWrongRate,
            groundTruthScores: truthScores,
            groundTruthNote: groundTruthNote
        )
    }
}

// MARK: - features.csv parsing

enum SessionLoader {

    static func load(sessionDir: URL) throws -> [TrackSegment] {
        let csvURL = sessionDir.appendingPathComponent("features.csv")
        let text = try String(contentsOf: csvURL, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return [] }

        let header = lines.removeFirst().split(separator: ",").map(String.init)
        var index: [String: Int] = [:]
        for (position, name) in header.enumerated() { index[name] = position }

        let required = ["track_elapsed_s", "beatPhase01", "drift_ms", "lock_state", "grid_bpm"]
        for column in required where index[column] == nil {
            throw ValidationError("features.csv is missing column '\(column)'")
        }

        func value(_ fields: [Substring], _ column: String) -> Double {
            guard let position = index[column], position < fields.count else { return 0 }
            return Double(fields[position]) ?? 0
        }

        var segments: [TrackSegment] = []
        var current: [SessionFrame] = []
        var previousElapsed = -1.0
        for line in lines {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= header.count - 2 else { continue }
            let elapsed = value(fields, "track_elapsed_s")
            // A reset of track_elapsed_s marks a track boundary.
            if previousElapsed >= 0 && elapsed < previousElapsed - 1.0 {
                if current.count > 100 { segments.append(TrackSegment(frames: current)) }
                current = []
            }
            current.append(SessionFrame(
                wallclock: value(fields, "wallclock_s"),
                trackElapsed: elapsed,
                beatPhase01: value(fields, "beatPhase01"),
                driftMs: value(fields, "drift_ms"),
                lockState: Int(value(fields, "lock_state")),
                gridBPM: value(fields, "grid_bpm")
            ))
            previousElapsed = elapsed
        }
        if current.count > 100 { segments.append(TrackSegment(frames: current)) }
        return segments
    }
}
