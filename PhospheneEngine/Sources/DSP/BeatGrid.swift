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

    /// Return a new grid with `beatsPerBar` overridden to a new value, keeping
    /// every other field (beats, downbeats, BPM, frameRate, frameCount,
    /// barConfidence) unchanged. Used by metadata-driven meter override
    /// when an external source (e.g. Spotify `/audio-features`'
    /// `time_signature`) provides a more reliable meter than the ML beat
    /// detector's auto-detected value. Round 25 (2026-05-15).
    public func overridingBeatsPerBar(_ newValue: Int) -> BeatGrid {
        let clamped = max(1, newValue)
        if clamped == beatsPerBar { return self }
        return BeatGrid(
            beats: beats,
            downbeats: downbeats,
            bpm: bpm,
            beatsPerBar: clamped,
            barConfidence: barConfidence,
            frameRate: frameRate,
            frameCount: frameCount
        )
    }

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

// MARK: - Octave Correction

extension BeatGrid {

    /// Return a copy with beats thinned so that BPM falls into the practical
    /// range [80, 175], correcting double-time detection from short audio windows.
    ///
    /// **Halving only** — BPM > 175 is halved (and every other beat is dropped);
    /// BPM < 80 is left unchanged because some tracks genuinely have slow tempos
    /// (e.g. Pyramid Song ~68 BPM) and doubling would be incorrect. The upper-bound
    /// correction is applied recursively until BPM ≤ 175.
    ///
    /// **Threshold rationale (BUG-009, 2026-05-07).** Originally 160 BPM. Raised
    /// to 175 because legitimate fast tracks live in [160, 175]: drum'n'bass
    /// (170–175), fast indie rock (Foo Fighters' "Everlong" ~158, Strokes / Arctic
    /// Monkeys 155–170), fast metal (180+ — still halved correctly). On the live
    /// 10-second Beat This! window, the analyser sometimes outputs 165–180 for a
    /// true ~158 BPM source; the old 160 threshold halved those down to ~85,
    /// producing a half-rate visual orb. 175 captures the fast-rock band without
    /// re-enabling true double-time errors (those land at ≥ 200 typically).
    ///
    /// Used exclusively by the live 10-second Beat This! trigger path in
    /// `VisualizerEngine+Stems`. The offline 30-second prep path does not need this
    /// because longer context produces reliable beat-level detection.
    ///
    /// After thinning, downbeats are re-snapped to the surviving beats within ±40 ms.
    /// Downbeats that fall on removed (odd-indexed) beats beyond the snap window are
    /// discarded; `beatsPerBar` is recalculated from the corrected downbeat set.
    public func halvingOctaveCorrected() -> BeatGrid {
        guard bpm > 175, beats.count >= 2 else { return self }

        var correctedBeats = beats
        var correctedBPM = bpm

        // Halve repeatedly until BPM ≤ 175 (handles pathological triple-time, etc.).
        while correctedBPM > 175, correctedBeats.count >= 2 {
            correctedBPM /= 2
            correctedBeats = stride(from: 0, to: correctedBeats.count, by: 2)
                .map { correctedBeats[$0] }
        }

        // Re-snap downbeats to surviving beats within ±40 ms (one downbeat per beat).
        let snapTolerance = 0.04
        var usedIndices = Set<Int>()
        let correctedDownbeats: [Double] = downbeats.compactMap { db in
            guard let idx = correctedBeats.indices.min(
                by: { abs(correctedBeats[$0] - db) < abs(correctedBeats[$1] - db) }
            ),
            abs(correctedBeats[idx] - db) <= snapTolerance,
            !usedIndices.contains(idx) else { return nil }
            usedIndices.insert(idx)
            return correctedBeats[idx]
        }

        // Recompute meter from corrected downbeats.
        let beatPeriod = correctedBPM > 0 ? 60.0 / correctedBPM : 0
        let (correctedBPB, correctedConf): (Int, Float) = {
            guard correctedDownbeats.count >= 2, beatPeriod > 0 else {
                return (beatsPerBar, barConfidence)
            }
            let dbIOIs = zip(correctedDownbeats, correctedDownbeats.dropFirst())
                .map { $1 - $0 }
            let sorted = dbIOIs.sorted()
            let median = sorted[sorted.count / 2]
            let bpb = max(1, Int((median / beatPeriod).rounded()))
            let matching = dbIOIs.filter {
                Int(($0 / beatPeriod).rounded()) == bpb
            }.count
            return (bpb, Float(matching) / Float(dbIOIs.count))
        }()

        return BeatGrid(
            beats: correctedBeats,
            downbeats: correctedDownbeats,
            bpm: correctedBPM,
            beatsPerBar: correctedBPB,
            barConfidence: correctedConf,
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
