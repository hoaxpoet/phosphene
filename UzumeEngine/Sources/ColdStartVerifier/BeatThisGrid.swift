// BeatThisGrid — One-beat-per-beat audible reference from Beat This!.
//
// CS.1 (option C) needs a genuine one-beat-per-beat audible reference — not an
// onset signal (`beatBass` fires >1×/beat, which pollutes a per-beat
// measurement). Beat This! is a beat *tracker*: it emits exactly one beat per
// beat. This module slices the per-track region out of raw_tap.wav and runs the
// engine's `DefaultBeatGridAnalyzer` (Beat This! preprocessing + MPSGraph
// inference + BeatGridResolver) on it.
//
// The slice is kept ≤ 25 s so the spectrogram stays under Beat This!'s
// `tMax = 1500` frames (30 s at 50 fps).

import Foundation
import Session

enum BeatThisGrid {

    /// Run Beat This! on a `[sliceStartS, sliceStartS + durationS]` slice of
    /// `samples` (raw-tap clock). Returns beat times in raw-tap clock — the
    /// slice-local Beat This! beats shifted back by the slice origin. Empty when
    /// the slice is too short or Beat This! returns no grid.
    static func beats(
        samples: [Float], sampleRate: Double,
        sliceStartS: Double, durationS: Double,
        analyzer: DefaultBeatGridAnalyzer
    ) -> [Double] {
        let startIdx = max(0, Int(sliceStartS * sampleRate))
        let endIdx = min(samples.count, startIdx + Int(durationS * sampleRate))
        guard endIdx - startIdx >= Int(sampleRate) else { return [] }   // need ≥ 1 s
        let slice = Array(samples[startIdx..<endIdx])
        let grid = analyzer.analyzeBeatGrid(samples: slice, sampleRate: sampleRate)
        let sliceOrigin = Double(startIdx) / sampleRate
        return grid.beats.map { $0 + sliceOrigin }
    }
}
