// TonalStatsTests — the pure aggregation math behind TonalDumper's calibration
// (TONAL.2). The corpus constants ride on percentile / circular-mean / window
// bucketing being correct, so they get unit coverage independent of audio.

import Testing
import Foundation
@testable import TonalDumper

@Suite("TonalStats — dumper aggregation math")
struct TonalStatsTests {

    // MARK: - percentile

    @Test("percentile interpolates and clamps")
    func percentileBasics() {
        let sorted = [0.0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]  // 11 values, 0…10
        #expect(TonalStats.percentile(sorted, 0.0) == 0)
        #expect(TonalStats.percentile(sorted, 1.0) == 10)
        #expect(TonalStats.percentile(sorted, 0.5) == 5)
        #expect(abs(TonalStats.percentile(sorted, 0.9) - 9) < 1e-9)
        #expect(TonalStats.percentile([], 0.5) == 0, "empty → 0")
        #expect(TonalStats.percentile([42], 0.9) == 42, "single element")
        #expect(TonalStats.percentile(sorted, 2.0) == 10, "p clamps to 1.0")
    }

    @Test("percentiles() returns the 8-point set keyed by p×100")
    func percentileSet() {
        let values = (0...100).map(Double.init)  // 0…100
        let pct = TonalStats.percentiles(values)
        #expect(abs((pct[50] ?? -1) - 50) < 1e-9)
        #expect(abs((pct[99] ?? -1) - 99) < 1e-9)
        #expect(abs((pct[1] ?? -1) - 1) < 1e-9)
        #expect(pct.count == 8)
    }

    // MARK: - circular mean

    @Test("circular mean averages angles across the ±π wrap correctly")
    func circularMeanWrap() {
        // Two angles straddling π: +170° and −170° average to 180° (±π), NOT 0°.
        let a = 170.0 * .pi / 180
        let b = -170.0 * .pi / 180
        let mean = TonalStats.circularMeanRadians([a, b])
        #expect(abs(abs(mean) - .pi) < 1e-6, "mean of ±170° is ±180°, not 0° (a naive mean fails here)")
        // A tight cluster averages to its center.
        #expect(abs(TonalStats.circularMeanRadians([0.1, 0.2, 0.3]) - 0.2) < 1e-6)
    }

    @Test("circular concentration is ~1 for aligned angles, ~0 for a uniform spread")
    func concentration() {
        #expect(TonalStats.circularConcentration([0.5, 0.5, 0.5]) > 0.999, "aligned → ~1")
        // Four angles evenly around the circle cancel out.
        let spread = [0.0, .pi / 2, .pi, 3 * .pi / 2]
        #expect(TonalStats.circularConcentration(spread) < 1e-6, "uniform → ~0")
    }

    // MARK: - windowing

    @Test("windowMeans buckets frames into fixed-duration windows")
    func windowing() {
        // 10 Hz, 1 s windows → 10 frames per window. 25 frames → 3 windows (10,10,5).
        let values = (0..<25).map { Double($0) }
        let means = TonalStats.windowMeans(values, fps: 10, windowSeconds: 1)
        #expect(means.count == 3)
        #expect(abs(means[0] - 4.5) < 1e-9, "mean of 0…9")
        #expect(abs(means[1] - 14.5) < 1e-9, "mean of 10…19")
        #expect(abs(means[2] - 22.0) < 1e-9, "mean of 20…24 (partial window)")
    }

    // MARK: - CSV

    @Test("parseCSVLine handles quoted fields with embedded commas")
    func csvParsing() {
        let line = "0-9/A/track, with comma.m4a,m4a,123,unknown"
        // Unquoted comma-in-path would mis-split; a real manifest quotes it:
        let quoted = "\"0-9/A/track, with comma.m4a\",m4a,123,unknown"
        let fields = TonalStats.parseCSVLine(quoted)
        #expect(fields[0] == "0-9/A/track, with comma.m4a")
        #expect(fields.count == 4)
        // Plain line splits on every comma.
        #expect(TonalStats.parseCSVLine(line).count == 5)
        // Escaped quotes ("") collapse to one.
        #expect(TonalStats.parseCSVLine("\"a\"\"b\",c")[0] == "a\"b")
    }

    @Test("splitLines handles CRLF (the Swift \\r\\n-grapheme gotcha) and LF alike")
    func crlfLineSplit() {
        // CRLF: Swift fuses \r\n into one grapheme, so split(separator:\"\\n\") fails.
        let crlf = "relpath,genre\r\na.m4a,rock\r\nb.m4a,jazz\r\n"
        let lines = TonalStats.splitLines(crlf)
        #expect(lines.count == 3, "header + 2 rows — NOT 1 (the CRLF bug)")
        #expect(lines[1] == "a.m4a,rock", "no trailing \\r left on the line")
        // Plain LF still works.
        #expect(TonalStats.splitLines("x\ny\nz").count == 3)
    }
}
