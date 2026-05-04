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
        let (beatsPerBar, barConf) = computeMeter(downbeats: downbeatTimes, bpm: bpm)
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

    /// Compute beatsPerBar and barConfidence from downbeat IOIs and bpm.
    ///
    /// Algorithm: `round(median_downbeat_IOI / beat_period)` — matches the Python
    /// reference `beats_per_bar_from_downbeats` function in `dump_beatthis_reference.py`.
    ///
    /// Returns (4, 0) when there are fewer than 2 downbeats or bpm is zero.
    private static func computeMeter(
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
        // barConfidence: fraction of IOIs whose rounded bpb matches the estimate.
        let matching = dbIOIs.filter { Int(($0 / beatPeriod).rounded()) == beatsPerBar }.count
        let confidence = Float(matching) / Float(dbIOIs.count)
        return (beatsPerBar, confidence)
    }
}
