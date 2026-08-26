// SessionPreparer+StemSeries — the full-file stem sweep (LFSTEM.1).
//
// Split from `SessionPreparer+Analysis.swift`, which was at its 400-line cap. The sweep is a
// self-contained pass over one decoded file and shares nothing with `analyzePreview` beyond
// the separator and analyzer it is handed.

import Foundation
import Audio
import DSP
import Shared

extension SessionPreparer {

    // MARK: - Full-file stem series (LFSTEM.1)

    /// Analysis hop the live path uses, and therefore the series grid.
    /// `VisualizerEngine+Audio.runPerFrameStemAnalysis` slides a 1024-sample window; a series
    /// on any coarser grid would not be a drop-in for what presets already consume.
    nonisolated static let seriesAnalysisHop = 1024

    /// Build a dense `StemFeatureSeries` covering the whole of `samples`.
    ///
    /// **The point of this function.** Live separation is late by construction: it can only
    /// analyse audio that has already played, so stem features reach presets ~2.5 s behind the
    /// music. Given the whole file up front — which local-file preparation already decodes —
    /// there is no reason to be late. Each frame is computed offline and handed to the renderer
    /// at the playback second it describes.
    ///
    /// **Window placement, which is the part that matters.** The separator works on a fixed
    /// window (~10 s). Rather than analysing each window whole and discarding most of it, this
    /// sweeps *kept spans* of `hopSeconds` in playback order and places each span at the END of
    /// its separation window wherever the audio allows:
    ///
    /// ```
    ///   window k:  [------------- ~10 s -------------]
    ///   kept:                                [ hop  ]
    /// ```
    ///
    /// That is deliberately the same relative position the live path reads from — live analyses
    /// the newest slice of the most recent separation — so the series carries the same character
    /// as the values presets were tuned against, only arriving on time instead of late. Near the
    /// start of the file the window cannot be pushed earlier, so the span sits wherever it falls
    /// inside the first window; those frames see less preceding context, exactly as they do live
    /// at track start.
    ///
    /// **AGC continuity.** One analyzer instance sweeps every span in playback order, so its
    /// band-energy AGC carries across span boundaries the way it does across live separations.
    /// Analysing spans independently would restart the AGC 120 times and put a discontinuity at
    /// every hop.
    ///
    /// - Parameters:
    ///   - samples: Fully decoded mono PCM for the whole track.
    ///   - sampleRate: Sample rate of `samples`.
    ///   - separator: Production separator. Its window length is read from the first result
    ///     rather than assumed, so a test double with a different window still works.
    ///   - analyzer: A FRESH analyzer — this function relies on owning its AGC state.
    ///   - hopSeconds: Playback seconds each separation contributes. 2.0 matches the live
    ///     separation period, so the offline sweep does the same amount of model work per second
    ///     of audio that live playback would.
    /// - Returns: The series, or `.empty` when there is too little audio to analyse.
    nonisolated public static func analyzeStemSeries(
        samples: [Float],
        sampleRate: Int,
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        hopSeconds: Double = 2.0
    ) throws -> StemFeatureSeries {
        let hop = Self.seriesAnalysisHop
        let sampleCount = samples.count
        guard sampleCount >= hop, sampleRate > 0, hopSeconds > 0 else { return .empty }

        let fps = Float(sampleRate) / Float(hop)
        let hopSamples = max(hop, Int(hopSeconds * Double(sampleRate)))
        let frameCount = sampleCount / hop
        var frames: [StemFeatures] = []
        frames.reserveCapacity(frameCount)

        var windowSamples = 0
        var spanStart = 0

        while spanStart < sampleCount {
            // Place the kept span at the window's end where the audio allows it — but leave
            // ONE analysis frame of room past the span, or the frame starting on the span's
            // last sample has no 1024 samples left inside the window and is silently dropped.
            // That cost 10 of 1292 frames over 30 s before `stemSeries_spanBoundariesDoNotDrift`
            // caught it: a per-span shortfall, invisible in any single span, compounding.
            let windowStart = windowSamples > 0
                ? max(0, spanStart + hopSamples + hop - windowSamples)
                : 0
            let windowEnd = windowSamples > 0
                ? min(sampleCount, windowStart + windowSamples)
                : sampleCount
            let window = Array(samples[windowStart..<max(windowStart, windowEnd)])

            // The separator pads-or-truncates to its own window, so the result's length IS the
            // window length — read it rather than hard-coding a constant from another module.
            let result = try separator.separate(
                audio: window, channelCount: 1, sampleRate: Float(sampleRate))
            let stems = result.stemWaveforms
            guard let stemLength = stems.first?.count, stemLength >= hop else { return .empty }
            if windowSamples == 0 { windowSamples = stemLength }

            // Emit every frame of the global 1024-sample grid whose start falls in this span.
            // Indexing globally (rather than counting within the span) keeps the grid uniform
            // even though hopSamples is not a whole number of analysis frames.
            let firstFrame = Int(ceil(Double(spanStart) / Double(hop)))
            let spanEnd = min(spanStart + hopSamples, sampleCount)
            var frameIndex = max(firstFrame, frames.count)
            while frameIndex * hop < spanEnd {
                let absolute = frameIndex * hop
                guard absolute + hop <= sampleCount else { break }
                let offset = absolute - windowStart
                guard offset >= 0, offset + hop <= stemLength else { break }
                let slice = stems.map { Array($0[offset..<(offset + hop)]) }
                frames.append(analyzer.analyze(stemWaveforms: slice, fps: fps))
                frameIndex += 1
            }

            spanStart += hopSamples
        }

        guard !frames.isEmpty else { return .empty }
        return StemFeatureSeries(frames: frames, hopSeconds: Double(hop) / Double(sampleRate))
    }
}
