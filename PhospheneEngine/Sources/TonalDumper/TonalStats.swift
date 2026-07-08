// TonalStats — pure aggregation math for TonalDumper (TONAL.2).
//
// Split from the AVFoundation/Metal-bound Dumper so the percentile + window
// bucketing + circular-mean logic is unit-testable without decoding audio
// (the calibration numbers ride on this math being right). See TonalDumperTests.

import Foundation

// MARK: - TonalStats

public enum TonalStats {

    /// Linear-interpolated percentile of an ascending-sorted array. `p` in 0…1.
    /// Empty → 0; single element → that element. Clamps `p`.
    public static func percentile(_ sortedAscending: [Double], _ fraction: Double) -> Double {
        guard let first = sortedAscending.first else { return 0 }
        guard sortedAscending.count > 1 else { return first }
        let clamped = min(1, max(0, fraction))
        let rank = clamped * Double(sortedAscending.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sortedAscending[lo] }
        let frac = rank - Double(lo)
        return sortedAscending[lo] * (1 - frac) + sortedAscending[hi] * frac
    }

    /// The percentile set reported for every calibration signal.
    public static let reportedPercentiles: [Double] = [0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.99]

    /// Percentile set of an unsorted sample (sorts a copy). Keys are the
    /// percentiles ×100 as ints (1, 5, 10, 25, 50, 75, 90, 99).
    public static func percentiles(_ values: [Double]) -> [Int: Double] {
        let sorted = values.sorted()
        var out: [Int: Double] = [:]
        for frac in reportedPercentiles { out[Int((frac * 100).rounded())] = percentile(sorted, frac) }
        return out
    }

    /// Mean of a set of angles (radians) on the circle — `atan2(Σsin, Σcos)`.
    /// The correct average for the wrapped fifths/thirds phase (a naive mean
    /// tears at ±π). Empty → 0.
    public static func circularMeanRadians(_ angles: [Double]) -> Double {
        guard !angles.isEmpty else { return 0 }
        var sumSin = 0.0
        var sumCos = 0.0
        for ang in angles { sumSin += sin(ang); sumCos += cos(ang) }
        if sumSin == 0 && sumCos == 0 { return 0 }
        return atan2(sumSin, sumCos)
    }

    /// Circular resultant length (0…1): 1 = all angles equal (stable phase),
    /// ~0 = uniformly spread (no tonal center). A useful "phase stability" read.
    public static func circularConcentration(_ angles: [Double]) -> Double {
        guard !angles.isEmpty else { return 0 }
        var sumSin = 0.0
        var sumCos = 0.0
        for ang in angles { sumSin += sin(ang); sumCos += cos(ang) }
        return (sumSin * sumSin + sumCos * sumCos).squareRoot() / Double(angles.count)
    }

    /// Bucket per-frame values into fixed-duration windows and return each
    /// window's mean. `phase` picks circular vs arithmetic mean. A short final
    /// partial window is included.
    public static func windowMeans(
        _ values: [Double], fps: Double, windowSeconds: Double, phase: Bool = false
    ) -> [Double] {
        guard !values.isEmpty, fps > 0, windowSeconds > 0 else { return [] }
        let per = max(1, Int((fps * windowSeconds).rounded()))
        var out: [Double] = []
        var idx = 0
        while idx < values.count {
            let slice = Array(values[idx..<min(idx + per, values.count)])
            out.append(phase ? circularMeanRadians(slice) : slice.reduce(0, +) / Double(slice.count))
            idx += per
        }
        return out
    }

    /// Median (p50) convenience.
    public static func median(_ values: [Double]) -> Double {
        percentile(values.sorted(), 0.5)
    }

    /// Split one CSV line into fields, honouring double-quoted fields with
    /// embedded commas and `""` escapes (the manifest relpaths can contain
    /// commas). Minimal RFC-4180 reader — enough for the pilot manifest.
    public static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var idx = 0
        while idx < chars.count {
            let ch = chars[idx]
            if inQuotes {
                if ch == "\"" {
                    if idx + 1 < chars.count && chars[idx + 1] == "\"" {
                        current.append("\"")
                        idx += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                fields.append(current); current = ""
            } else {
                current.append(ch)
            }
            idx += 1
        }
        fields.append(current)
        return fields
    }
}
