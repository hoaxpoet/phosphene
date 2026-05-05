// BeatGrid — Offline beat/downbeat grid resolved from Beat This! model output.
//
// Produced once per track by BeatGridResolver during pre-analysis of the 30-second
// preview clip. Cached on CachedTrackData (Session module, S6) for instant playback
// access by LiveBeatDriftTracker.
//
// Lives in DSP (not Session) so that BeatGridResolver, which is also in DSP, can
// return it without creating a circular dependency (Session imports DSP, not vice versa).
// TrackProfile / CachedTrackData in Session reference BeatGrid via the DSP import.

import Foundation

// MARK: - BeatGrid

/// Resolved offline beat grid for one track.
///
/// All times are in seconds, derived from a 50 fps (hop=441, sr=22050) frame grid.
/// `beatsPerBar` and `barConfidence` reflect the meter estimated from downbeat spacing.
public struct BeatGrid: Sendable, Hashable, Codable {

    // MARK: - Fields

    /// Beat positions in seconds (ascending). Includes downbeat positions.
    public let beats: [Double]

    /// Downbeat positions in seconds (ascending). Subset of `beats` — each downbeat
    /// is snapped to its nearest beat within ±40 ms.
    public let downbeats: [Double]

    /// Tempo in BPM from trimmed-mean IOI. 0.0 if fewer than 4 beats were detected.
    public let bpm: Double

    /// Estimated beats per bar (e.g. 4 for 4/4, 3 for 3/4, 2 for 2/4).
    /// Computed as `round(median_downbeat_IOI / beat_period)`.
    /// Defaults to 4 when there are fewer than 2 downbeat pairs or bpm == 0.
    public let beatsPerBar: Int

    /// Fraction of inter-downbeat intervals consistent with `beatsPerBar`. Range 0–1.
    /// 0 when there are fewer than 2 downbeat pairs or when bpm == 0.
    public let barConfidence: Float

    /// Frame rate used during resolution (Beat This! = 50.0 fps).
    public let frameRate: Double

    /// Number of frames the resolver was called with (input length, not beat count).
    public let frameCount: Int

    // MARK: - Init

    public init(
        beats: [Double],
        downbeats: [Double],
        bpm: Double,
        beatsPerBar: Int,
        barConfidence: Float,
        frameRate: Double,
        frameCount: Int
    ) {
        self.beats = beats
        self.downbeats = downbeats
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.barConfidence = barConfidence
        self.frameRate = frameRate
        self.frameCount = frameCount
    }

    // MARK: - Convenience

    /// Empty grid — no beats, no downbeats, bpm 0, default 4/4, confidence 0.
    public static let empty = BeatGrid(
        beats: [],
        downbeats: [],
        bpm: 0.0,
        beatsPerBar: 4,
        barConfidence: 0,
        frameRate: 50.0,
        frameCount: 0
    )
}

// MARK: - Transformation

extension BeatGrid {

    /// Return a new grid with all beat and downbeat times shifted by `seconds`,
    /// then extrapolated forward to `horizon` seconds past the last shifted beat.
    ///
    /// Used when a BeatGrid is analyzed from a buffer window that starts at some
    /// offset within the track (e.g. the last 10 seconds of live tap audio). Add
    /// `trackStartOffset` so beat times align with the track-relative playback
    /// clock used by `LiveBeatDriftTracker`.
    ///
    /// Without forward extrapolation the grid only covers ~10 seconds of beats from
    /// the live-trigger window. Once `playbackTime` passes the last recorded beat,
    /// `computePhase` clamps `beatPhase01` at 1.0 and `nearestBeat` can never find
    /// a match within ±50 ms, so `consecutiveMisses` grows indefinitely and the
    /// tracker never reaches `.locked`. Extrapolating to 300 s makes the grid
    /// effectively infinite for a typical session.
    public func offsetBy(_ seconds: Double, horizon: Double = 300.0) -> BeatGrid {
        var shiftedBeats = beats.map { $0 + seconds }
        var shiftedDownbeats = downbeats.map { $0 + seconds }

        // Extrapolate forward using the stored BPM so the grid covers
        // future playback without requiring another Beat This! inference.
        if let lastBeat = shiftedBeats.last, bpm > 0 {
            let period = 60.0 / bpm
            let ceiling = lastBeat + horizon
            var next = lastBeat + period
            while next <= ceiling {
                shiftedBeats.append(next)
                next += period
            }
            // Extrapolate downbeats at the bar period.
            let dbPeriod = period * Double(max(beatsPerBar, 1))
            let dbBase = shiftedDownbeats.last ?? lastBeat
            let dbCeiling = dbBase + horizon
            var nextDb = dbBase + dbPeriod
            while nextDb <= dbCeiling {
                shiftedDownbeats.append(nextDb)
                nextDb += dbPeriod
            }
        }

        return BeatGrid(
            beats: shiftedBeats,
            downbeats: shiftedDownbeats,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            barConfidence: barConfidence,
            frameRate: frameRate,
            frameCount: frameCount
        )
    }
}

// MARK: - Lookup Helpers

extension BeatGrid {

    /// Median IOI across consecutive beats. Falls back to `60 / bpm` when fewer
    /// than two beats; 0 if the grid carries no tempo information.
    public var medianBeatPeriod: Double {
        guard beats.count >= 2 else {
            return bpm > 0 ? 60.0 / bpm : 0.0
        }
        var iois: [Double] = []
        iois.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count {
            iois.append(beats[i] - beats[i - 1])
        }
        iois.sort()
        return iois[iois.count / 2]
    }

    /// Index of the beat at-or-immediately-before `time`. `nil` if `time` is
    /// strictly before the first beat or the grid is empty. Bisect search —
    /// O(log n) — so safe on long grids.
    public func beatIndex(at time: Double) -> Int? {
        guard !beats.isEmpty, time >= beats[0] else { return nil }
        var lo = 0
        var hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if beats[mid] <= time {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// Local timing at `time`: the beat period (current-to-next IOI, or
    /// `60/bpm` past the last beat) plus the count of beats since the most
    /// recent downbeat. Returns nil if `time` is before the first beat.
    public func localTiming(at time: Double) -> (period: Double, beatsSinceDownbeat: Int)? {
        guard let idx = beatIndex(at: time) else { return nil }
        let period: Double
        if idx + 1 < beats.count {
            period = beats[idx + 1] - beats[idx]
        } else if bpm > 0 {
            period = 60.0 / bpm
        } else {
            period = 0.5
        }
        let beatsSince = beatsSinceDownbeat(beatIndex: idx)
        return (period, beatsSince)
    }

    /// Nearest beat to `time` whose absolute distance is ≤ `window` seconds, or
    /// nil if no beat falls within. Internal helper for LiveBeatDriftTracker.
    func nearestBeat(to time: Double, within window: Double) -> Double? {
        guard !beats.isEmpty else { return nil }
        var lo = 0
        var hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if beats[mid] < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var best = Double.infinity
        var bestVal: Double?
        for cand in [lo - 1, lo] where cand >= 0 && cand < beats.count {
            let dist = abs(beats[cand] - time)
            if dist < best {
                best = dist
                bestVal = beats[cand]
            }
        }
        guard best <= window else { return nil }
        return bestVal
    }

    /// Beats since the most recent downbeat at-or-before the beat at `beatIndex`.
    /// Falls back to `beatIndex % beatsPerBar` if no downbeats are available
    /// (or `time` precedes the first downbeat).
    private func beatsSinceDownbeat(beatIndex idx: Int) -> Int {
        let bpb = max(beatsPerBar, 1)
        guard !downbeats.isEmpty else {
            return idx % bpb
        }
        let beatTime = beats[idx]
        guard beatTime + 0.005 >= downbeats[0] else {
            return idx % bpb
        }
        var lo = 0
        var hi = downbeats.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if downbeats[mid] <= beatTime + 0.005 {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let dbTime = downbeats[lo]
        guard let dbBeatIdx = beatIndex(at: dbTime + 0.001) else {
            return idx % bpb
        }
        return max(0, idx - dbBeatIdx)
    }
}
