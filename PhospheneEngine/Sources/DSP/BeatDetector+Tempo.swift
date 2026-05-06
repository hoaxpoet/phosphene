// BeatDetector+Tempo — Tempo estimation via IOI histograms and autocorrelation.

import Foundation
import Accelerate

/// Result of building an inter-onset interval histogram.
struct IOIHistogramResult {
    var bestBPM: Float
    var peakCount: Int
    var histogram: [Int]
    var inRange: Int
    var outOfRange: Int
}

// MARK: - Shared Helpers

extension BeatDetector {
    /// Compute RMS of magnitude bins in each of the 6 bands.
    func computeBandRMS(magnitudes: [Float]) -> [Float] {
        bandRanges.map { range in
            let start = range.start
            let end = min(range.end, magnitudes.count)
            let count = end - start
            guard count > 0 else { return Float(0) }

            var rms: Float = 0
            magnitudes.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(count))
            }
            return rms
        }
    }

    /// Compute median of the first `count` elements in a buffer.
    func medianOfBuffer(_ buffer: [Float], count: Int) -> Float {
        guard count > 0 else { return 0 }
        let slice = Array(buffer.prefix(count)).sorted()
        if count % 2 == 0 {
            return (slice[count / 2 - 1] + slice[count / 2]) / 2.0
        }
        return slice[count / 2]
    }

    /// Compute a given percentile (0–1) of the first `count` elements in a buffer.
    func percentileOfBuffer(_ buffer: [Float], count: Int, percentile: Float) -> Float {
        guard count > 0 else { return 0 }
        let slice = Array(buffer.prefix(count)).sorted()
        let idx = min(Int(Float(count) * percentile), count - 1)
        return slice[idx]
    }
}

// MARK: - Stable Tempo (IOI Histogram)

extension BeatDetector {
    /// Compute stable tempo from inter-onset intervals using histogram + hysteresis.
    /// Called once per second from process(). Must be called under lock.
    func computeStableTempo() {
        let recentTimestamps = collectRecentTimestamps()

        guard recentTimestamps.count >= 4 else {
            let firstTs = recentTimestamps.first ?? .infinity
            let lastTs = recentTimestamps.last ?? -.infinity
            tempoDebug = String(
                format: "recent<4(%d) e=%.1f ws=%.1f first=%.1f last=%.1f buf=%d",
                recentTimestamps.count,
                elapsedTime,
                elapsedTime - 10.0,
                firstTs,
                lastTs,
                onsetTimestampCount
            )
            dumpEarly(label: "stable", reason: tempoDebug)
            return
        }

        // Build IOI histogram and find best BPM.
        let histResult = buildIOIHistogram(from: recentTimestamps)

        guard histResult.peakCount >= 2 else {
            tempoDebug = "noPeak(in=\(histResult.inRange),"
                + "out=\(histResult.outOfRange),"
                + "recent=\(recentTimestamps.count))"
            dumpEarly(label: "stable", reason: tempoDebug)
            return
        }

        // Robust BPM from trimmed-mean IOI; avoids histogram bucket
        // quantization bias toward faster BPMs. See D-073.
        let correctedBPM = computeRobustBPM(from: recentTimestamps)
        guard correctedBPM > 0 else {
            tempoDebug = "robustBPM=0 recent=\(recentTimestamps.count)"
            dumpEarly(label: "stable", reason: tempoDebug)
            return
        }

        instantBPM = correctedBPM

        dumpHistogram(label: "stable", hist: histResult.histogram, raw: histResult.bestBPM, sel: correctedBPM)

        // Diagnostic log.
        let ioiValues = (1..<recentTimestamps.count).map {
            recentTimestamps[$0] - recentTimestamps[$0 - 1]
        }
        let avgIOI = ioiValues.isEmpty ? 0 : ioiValues.reduce(0, +) / Double(ioiValues.count)
        let minIOI = ioiValues.min() ?? 0
        let peakBucket = Int(round(histResult.bestBPM)) - 60
        tempoDebug = String(
            format: "ok r=%d bpm=%.0f pk=%d@%d avg_ioi=%.3f min_ioi=%.3f",
            recentTimestamps.count,
            correctedBPM,
            histResult.peakCount,
            peakBucket + 60,
            avgIOI,
            minIOI
        )

        // Apply hysteresis filtering.
        applyTempoHysteresis(correctedBPM)
    }

    // MARK: - Stable Tempo Helpers

    /// Collect onset timestamps from the last 10 seconds of the sliding window.
    private func collectRecentTimestamps() -> [Double] {
        let windowStart = elapsedTime - 10.0
        var recentTimestamps = [Double]()
        recentTimestamps.reserveCapacity(onsetTimestampCount)

        for i in 0..<onsetTimestampCount {
            let idx = (onsetTimestampHead - onsetTimestampCount + i
                       + Self.onsetTimestampWindowSize) % Self.onsetTimestampWindowSize
            let ts = onsetTimestamps[idx]
            if ts >= windowStart {
                recentTimestamps.append(ts)
            }
        }
        return recentTimestamps
    }

    /// Build an IOI histogram from timestamps and return the peak BPM, count, histogram,
    /// and in-range/out-of-range counts.
    private func buildIOIHistogram(from timestamps: [Double]) -> IOIHistogramResult {
        var histogram = [Int](repeating: 0, count: 141)  // indices 0..140 -> BPM 60..200
        var outOfRange = 0
        var inRange = 0

        for i in 1..<timestamps.count {
            let ioi = timestamps[i] - timestamps[i - 1]
            guard ioi > 0.01 else { continue }
            let bpm = 60.0 / ioi
            let bucket = Int(round(bpm)) - 60
            if bucket >= 0 && bucket < 141 {
                histogram[bucket] += 1
                inRange += 1
            } else {
                outOfRange += 1
            }
        }

        // Find peak bucket.
        var peakCount = 0
        var peakBucket = 0
        for i in 0..<141 where histogram[i] > peakCount {
            peakCount = histogram[i]
            peakBucket = i
        }

        return IOIHistogramResult(
            bestBPM: Float(peakBucket + 60),
            peakCount: peakCount,
            histogram: histogram,
            inRange: inRange,
            outOfRange: outOfRange
        )
    }

    /// Robust BPM from recent IOI timestamps. Replaces the histogram-mode
    /// pick (which has bucket quantization bias toward faster BPMs since
    /// BPM buckets get wider in period space as BPM increases). Computes
    /// median IOI, then trimmed mean of IOIs within [0.5x, 2x] of median
    /// to reject outliers from dropped beats or occasional fills.
    private func computeRobustBPM(from timestamps: [Double]) -> Float {
        guard timestamps.count >= 4 else { return 0 }
        let iois = (1..<timestamps.count).map { timestamps[$0] - timestamps[$0 - 1] }
        let sorted = iois.sorted()
        let median = sorted[sorted.count / 2]
        let lo = median * 0.5
        let hi = median * 2.0
        let inliers = iois.filter { $0 >= lo && $0 <= hi }
        guard !inliers.isEmpty else { return 0 }
        let meanIOI = inliers.reduce(0, +) / Double(inliers.count)
        guard meanIOI > 0 else { return 0 }
        var bpm = Float(60.0 / meanIOI)
        // Halving-only octave correction. Sub-80 doubling was deleted in QR.1
        // (D-079) — Pyramid Song genuinely runs at ~68 BPM and any track in
        // [40, 80) BPM is preserved. This matches BeatGrid.halvingOctaveCorrected.
        if bpm > 160 { bpm /= 2 }
        return bpm
    }

    /// Apply hysteresis filtering to a new tempo estimate.
    private func applyTempoHysteresis(_ newInstant: Float) {
        tempoEstimates[tempoEstimateHead] = newInstant
        tempoEstimateHead = (tempoEstimateHead + 1) % Self.tempoEstimateBufferSize
        tempoEstimateCount = min(tempoEstimateCount + 1, Self.tempoEstimateBufferSize)

        // Compute median of the estimates buffer.
        let validEstimates = Array(tempoEstimates.prefix(tempoEstimateCount)).sorted()
        let median: Float
        if validEstimates.count % 2 == 0 {
            median = (validEstimates[validEstimates.count / 2 - 1]
                      + validEstimates[validEstimates.count / 2]) / 2.0
        } else {
            median = validEstimates[validEstimates.count / 2]
        }

        // Hysteresis: only update stableBPM when filtered estimate agrees for 3+ estimates.
        if abs(median - candidateBPM) <= 5.0 {
            stableConsecutiveCount += 1
        } else {
            candidateBPM = median
            stableConsecutiveCount = 1
        }

        if stableConsecutiveCount >= 3 {
            stableBPM = candidateBPM
        }
    }
}

// MARK: - Autocorrelation Tempo Estimation

extension BeatDetector {
    /// Estimate tempo via autocorrelation of the onset history.
    func estimateTempo() -> (tempo: Float?, confidence: Float) {
        guard onsetHistoryCount >= Self.minTempoFrames else { return (nil, 0) }

        let fps = currentFps
        guard fps > 0 else { return (nil, 0) }

        // Search BPM range: 60–200 BPM.
        let minLag = Int(60.0 * fps / 200.0)  // ~18 frames at 60fps for 200 BPM
        let maxLag = Int(60.0 * fps / 60.0)   // ~60 frames at 60fps for 60 BPM

        guard minLag > 0 && maxLag > minLag && maxLag < onsetHistoryCount else {
            return (nil, 0)
        }

        // Linearize the circular buffer.
        let linear = linearizeOnsetHistory()
        let effectiveMaxLag = min(maxLag, onsetHistoryCount / 2)

        // Find best autocorrelation lag.
        let (bestLag, bestCorrelation) = findBestLag(
            linear: linear, minLag: minLag, maxLag: effectiveMaxLag
        )
        guard bestLag > 0 else { return (nil, 0) }

        // Check half-lag (octave correction) and compute BPM.
        var bpm = correctForHalfLag(
            linear: linear,
            bestLag: bestLag,
            bestCorrelation: bestCorrelation,
            minLag: minLag,
            fps: fps
        )

        // Halving-only octave correction (matches computeRobustBPM and
        // BeatGrid.halvingOctaveCorrected). Sub-80 doubling deleted in QR.1
        // (D-079) so genuinely slow tracks (Pyramid Song ~68 BPM) survive.
        if bpm > 160 { bpm /= 2 }

        // Compute confidence.
        let confidence = computeAutocorrelationConfidence(
            linear: linear,
            bestCorrelation: bestCorrelation,
            minLag: minLag,
            maxLag: effectiveMaxLag
        )

        return (bpm, confidence)
    }

    // MARK: - Autocorrelation Helpers

    /// Linearize the circular onset history buffer into a contiguous array.
    private func linearizeOnsetHistory() -> [Float] {
        var linear = [Float](repeating: 0, count: onsetHistoryCount)
        for i in 0..<onsetHistoryCount {
            let idx = (onsetHistoryHead - onsetHistoryCount + i
                       + Self.onsetHistorySize) % Self.onsetHistorySize
            linear[i] = onsetHistory[idx]
        }
        return linear
    }

    /// Find the lag with the highest autocorrelation in the given range.
    private func findBestLag(
        linear: [Float],
        minLag: Int,
        maxLag: Int
    ) -> (lag: Int, correlation: Float) {
        var bestCorrelation: Float = 0
        var bestLag = 0

        for lag in minLag...maxLag {
            var correlation: Float = 0
            let overlapCount = linear.count - lag
            let lagged = Array(linear[lag..<lag + overlapCount])

            vDSP_dotpr(
                linear,
                1,
                lagged,
                1,
                &correlation,
                vDSP_Length(overlapCount)
            )
            correlation /= Float(overlapCount)

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }
        return (bestLag, bestCorrelation)
    }

    /// Check if the half-lag (double BPM) has strong correlation and prefer it if so.
    private func correctForHalfLag(
        linear: [Float],
        bestLag: Int,
        bestCorrelation: Float,
        minLag: Int,
        fps: Float
    ) -> Float {
        var bpm = 60.0 * fps / Float(bestLag)

        let halfLag = bestLag / 2
        if halfLag >= minLag {
            var halfCorr: Float = 0
            let overlapHalf = linear.count - halfLag
            let lagged = Array(linear[halfLag..<halfLag + overlapHalf])

            vDSP_dotpr(
                linear,
                1,
                lagged,
                1,
                &halfCorr,
                vDSP_Length(overlapHalf)
            )
            halfCorr /= Float(overlapHalf)
            if halfCorr > bestCorrelation * 0.6 {
                bpm = 60.0 * fps / Float(halfLag)
            }
        }
        return bpm
    }

    /// Compute confidence as ratio of best correlation to mean correlation.
    private func computeAutocorrelationConfidence(
        linear: [Float],
        bestCorrelation: Float,
        minLag: Int,
        maxLag: Int
    ) -> Float {
        var meanCorrelation: Float = 0
        var count = 0
        for lag in minLag...maxLag {
            var corr: Float = 0
            let overlapCount = linear.count - lag
            let lagged = Array(linear[lag..<lag + overlapCount])

            vDSP_dotpr(
                linear,
                1,
                lagged,
                1,
                &corr,
                vDSP_Length(overlapCount)
            )
            corr /= Float(overlapCount)
            meanCorrelation += corr
            count += 1
        }
        meanCorrelation /= Float(max(count, 1))

        return meanCorrelation > 1e-10
            ? min(bestCorrelation / meanCorrelation / 3.0, 1.0)
            : 0
    }
}
