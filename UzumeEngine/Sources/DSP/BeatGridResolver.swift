// BeatGridResolver — Offline beat/downbeat post-processor.
//
// Converts per-frame beat and downbeat probability streams (sigmoid-applied,
// range 0–1) from BeatThisModel into a resolved BeatGrid.
//
// Algorithm matches Beat This! minimal postprocessor (postprocessor.py §4.1 audit):
//   1. 7-frame max-pool → keep local maxima above 0.5 threshold
//   2. Adjacent-peak dedup: within ±1 frame, keep the higher-probability frame
//   3. Snap downbeat candidates to nearest beat within ±2 frames (40 ms)
//   4. BPM via trimmed-mean IOI (D-075 method, avoids histogram bias)
//   5. beatsPerBar via round(median_downbeat_IOI / beat_period)
//
// All allocations are local to resolve() — safe to call from any thread.

import Foundation

// MARK: - BeatGridResolver

/// Pure stateless resolver: beat+downbeat sigmoid probabilities → BeatGrid.
public struct BeatGridResolver {

    // MARK: - Constants

    static let maxPoolHalfKernel = 3    // ±3 frames = ±60 ms window at 50 fps
    static let probThreshold: Float = 0.5
    static let snapFrames = 2           // downbeat snap tolerance: ±2 frames = ±40 ms at 50 fps

    // MARK: - Public API

    /// Resolve probability streams into a BeatGrid.
    ///
    /// - Parameters:
    ///   - beatProbs:     Per-frame beat probabilities (sigmoid-applied), range 0–1.
    ///   - downbeatProbs: Per-frame downbeat probabilities (sigmoid-applied), range 0–1.
    ///   - frameRate:     Frames per second. Beat This! uses 50.0 (hop=441/sr=22050).
    /// - Returns: Resolved `BeatGrid` with beat times, downbeat times, BPM, and meter.
    public static func resolve(
        beatProbs: [Float],
        downbeatProbs: [Float],
        frameRate: Double
    ) -> BeatGrid {
        let beatFrames = peakPick(probs: beatProbs)
        let downbeatCandidateFrames = peakPick(probs: downbeatProbs)
        let beatTimes = beatFrames.map { Double($0) / frameRate }
        let candidateTimes = downbeatCandidateFrames.map { Double($0) / frameRate }
        let snapDist = Double(snapFrames) / frameRate
        let downbeatTimes = snapToBeats(candidates: candidateTimes, beats: beatTimes, maxDistance: snapDist)
        let bpm = computeBPM(beats: beatTimes)
        let (beatsPerBar, barConf) = computeMeter(
            downbeats: downbeatTimes, beats: beatTimes, bpm: bpm)
        return BeatGrid(
            beats: beatTimes,
            downbeats: downbeatTimes,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            barConfidence: barConf,
            frameRate: frameRate,
            frameCount: beatProbs.count
        )
    }

    // MARK: - Peak Picking

    /// 7-frame max-pool + local-maximum threshold + adjacent-peak dedup.
    ///
    /// Equivalent to PyTorch:
    ///   `sigmoid(logits[i]) > 0.5 AND sigmoid(logits[i]) == max_pool1d(sigmoid(logits), 7)[i]`
    /// followed by `deduplicate_peaks(width=1)`.
    private static func peakPick(probs: [Float]) -> [Int] {
        let frameCount = probs.count
        guard frameCount > 0 else { return [] }
        let halfK = maxPoolHalfKernel
        let thresh = probThreshold

        // Collect candidate local-maximum frames above threshold.
        var candidates = [Int]()
        for i in 0..<frameCount {
            guard probs[i] > thresh else { continue }
            let start = max(0, i - halfK)
            let end = min(frameCount - 1, i + halfK)
            var windowMax = probs[i]
            for j in start...end where probs[j] > windowMax { windowMax = probs[j] }
            if probs[i] == windowMax {
                candidates.append(i)
            }
        }
        guard !candidates.isEmpty else { return [] }

        // Dedup: merge adjacent frames (distance ≤ 1), keep highest probability.
        var peaks = [Int]()
        peaks.reserveCapacity(candidates.count)
        var groupStart = 0
        for k in 1...candidates.count {
            let isLast = k == candidates.count
            let nextIsAdjacent = !isLast && (candidates[k] - candidates[k - 1] <= 1)
            if !nextIsAdjacent {
                guard let best = (groupStart..<k).max(by: { probs[candidates[$0]] < probs[candidates[$1]] }) else {
                    groupStart = k; continue
                }
                peaks.append(candidates[best])
                groupStart = k
            }
        }
        return peaks
    }

    // MARK: - Downbeat Snapping

    /// Snap each downbeat candidate to the nearest beat within `maxDistance` seconds.
    /// Discards candidates outside the tolerance. Deduplicates: each beat can host
    /// at most one downbeat (first candidate wins on tie).
    private static func snapToBeats(
        candidates: [Double],
        beats: [Double],
        maxDistance: Double
    ) -> [Double] {
        guard !beats.isEmpty else { return [] }
        var result = [Double]()
        var usedBeatIndices = Set<Int>()
        result.reserveCapacity(candidates.count)
        for cand in candidates {
            var nearestIdx = 0
            var nearestDist = abs(beats[0] - cand)
            for i in 1..<beats.count {
                let dist = abs(beats[i] - cand)
                if dist < nearestDist {
                    nearestDist = dist
                    nearestIdx = i
                }
            }
            if nearestDist <= maxDistance && !usedBeatIndices.contains(nearestIdx) {
                result.append(beats[nearestIdx])
                usedBeatIndices.insert(nearestIdx)
            }
        }
        return result
    }

    // MARK: - BPM

    /// Trimmed-mean IOI BPM. Returns 0.0 for fewer than 4 beat times.
    ///
    /// Algorithm: median IOI → reject outliers outside [0.5×, 2×] median → mean of
    /// inliers → 60 / meanIOI. Matches BeatDetector.computeRobustBPM (D-075 method).
    static func computeBPM(beats: [Double]) -> Double {
        guard beats.count >= 4 else { return 0.0 }
        let iois = zip(beats, beats.dropFirst()).map { $1 - $0 }
        let sorted = iois.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return 0.0 }
        let inliers = iois.filter { $0 >= median * 0.5 && $0 <= median * 2.0 }
        guard !inliers.isEmpty else { return 0.0 }
        let meanIOI = inliers.reduce(0, +) / Double(inliers.count)
        guard meanIOI > 0 else { return 0.0 }
        return 60.0 / meanIOI
    }

    // MARK: - Meter

    /// Compute beatsPerBar and barConfidence by COUNTING the beats in each bar.
    ///
    /// The meter is "how many beats are in a bar", and `beats` holds the beats — so this
    /// counts them, rather than dividing a downbeat interval by a period.
    ///
    /// **Why it changed (PR.12, Matt 2026-09-04: "you should not be averaging BPM / tempo").**
    /// The previous algorithm was `round(median_downbeat_IOI / (60 / bpm))`, and `bpm` is
    /// `computeBPM`'s mean of the inlier inter-onset intervals across the WHOLE input. On a
    /// track whose tempo moves, that average is a period the music is never at, so bars in
    /// faster sections divided high and bars in slower sections divided low — and a wrong
    /// average produced a wrong meter even when every downbeat was in the right place. That
    /// is the mechanism behind the degenerate meters seen all through the 2026-09-04 roster
    /// review (bleed 4/4 read as 2, money 7/4 as 1, and `beatsPerBar = 2` on three of Bowie's
    /// Low tracks, PR.1 §2).
    ///
    /// Counting is immune to that: it never forms a period, so it cannot be wrong about one.
    /// Downbeats are snapped onto beats upstream (`snapToBeats`), so the half-open interval
    /// `[downbeat_i, downbeat_i+1)` contains exactly the bar's beats, including its own
    /// downbeat — 4 for a 4/4 bar.
    ///
    /// `beatsPerBar` is the MODE of the per-bar counts, not the median: meter is categorical,
    /// and the mode survives a few missed downbeats that would drag a median between values.
    /// `barConfidence` is the fraction of bars agreeing with it.
    ///
    /// Falls back to the period-division form when `beats` is empty, so a caller that has
    /// downbeats without beats degrades as before rather than failing.
    ///
    /// Returns (4, 0) when there are fewer than 2 downbeats.
    private static func computeMeter(
        downbeats: [Double],
        beats: [Double],
        bpm: Double
    ) -> (beatsPerBar: Int, barConfidence: Float) {
        guard downbeats.count >= 2 else { return (4, 0) }
        guard !beats.isEmpty else { return legacyMeterFromPeriod(downbeats: downbeats, bpm: bpm) }

        // Beats per bar, counted. `epsilon` absorbs the float error in a snapped downbeat
        // that should compare exactly equal to its beat.
        let epsilon = 1e-6
        var counts: [Int] = []
        for (start, end) in zip(downbeats, downbeats.dropFirst()) {
            let beatsInBar = beats.reduce(into: 0) { acc, beat in
                if beat >= start - epsilon && beat < end - epsilon { acc += 1 }
            }
            if beatsInBar > 0 { counts.append(beatsInBar) }
        }
        guard !counts.isEmpty else { return legacyMeterFromPeriod(downbeats: downbeats, bpm: bpm) }

        var histogram: [Int: Int] = [:]
        for count in counts { histogram[count, default: 0] += 1 }
        // Ties break toward the larger meter: a bar undercounted by a missed beat is a more
        // common error than one overcounted by a spurious beat.
        guard let beatsPerBar = histogram.max(by: {
            $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key
        })?.key else { return legacyMeterFromPeriod(downbeats: downbeats, bpm: bpm) }

        let matching = counts.filter { $0 == beatsPerBar }.count
        return (max(1, beatsPerBar), Float(matching) / Float(counts.count))
    }

    /// The pre-PR.12 meter: `round(median_downbeat_IOI / beat_period)` against the averaged
    /// `bpm`, matching the Python reference `beats_per_bar_from_downbeats`. Retained only for
    /// the no-beats path.
    private static func legacyMeterFromPeriod(
        downbeats: [Double],
        bpm: Double
    ) -> (beatsPerBar: Int, barConfidence: Float) {
        guard downbeats.count >= 2, bpm > 0 else { return (4, 0) }
        let dbIOIs = zip(downbeats, downbeats.dropFirst()).map { $1 - $0 }
        let sortedIOIs = dbIOIs.sorted()
        let median = sortedIOIs[sortedIOIs.count / 2]
        let beatPeriod = 60.0 / bpm
        guard beatPeriod > 0 else { return (4, 0) }
        let beatsPerBar = max(1, Int((median / beatPeriod).rounded()))
        let matching = dbIOIs.filter { Int(($0 / beatPeriod).rounded()) == beatsPerBar }.count
        return (beatsPerBar, Float(matching) / Float(dbIOIs.count))
    }
}
