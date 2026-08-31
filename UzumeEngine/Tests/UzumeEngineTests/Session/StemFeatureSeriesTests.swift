// StemFeatureSeriesTests — LFSTEM.1's alignment gate.
//
// The whole value of a pre-analysed stem series is that frame N describes playback second N.
// Everything else about it is an optimisation; alignment is the feature. A series that is
// correct but offset by one separation window would look perfectly healthy in every summary
// statistic and be WORSE than the live path it replaces — the failure mode BUG-096 and the
// render-clock/musical-clock confusion both produced, where a plausible number was computed
// against the wrong clock.
//
// So these tests assert timing against a signal whose timing is known by construction, not
// the plausibility of the values.

import Foundation
import Testing
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

// MARK: - FixedWindowSeparator

/// A separator double that reproduces the ONE property of `StemSeparator` this code depends
/// on: `separate()` pads-or-truncates its input to a fixed window (`requiredMonoSamples`,
/// 440320 in production) and returns waveforms of exactly that length.
///
/// `FakeStemSeparator` returns whatever length it is handed, which makes the window degenerate
/// and would let a window-placement bug pass unnoticed. Content is copied into all four stems
/// so every stem's energy tracks the input.
private final class FixedWindowSeparator: StemSeparating, @unchecked Sendable {

    let windowSamples: Int
    private(set) var separateCallCount = 0
    /// Window start offsets requested, in call order — lets a test assert placement directly.
    private(set) var receivedLengths: [Int] = []

    init(windowSamples: Int) { self.windowSamples = windowSamples }

    var stemLabels: [String] { ["vocals", "drums", "bass", "other"] }
    var stemBuffers: [UMABuffer<Float>] { [] }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        separateCallCount += 1
        receivedLengths.append(audio.count)
        var padded = [Float](repeating: 0, count: windowSamples)
        for i in 0..<min(windowSamples, audio.count) { padded[i] = audio[i] }
        let frame = AudioFrame(sampleRate: sampleRate,
                               sampleCount: UInt32(windowSamples), channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: windowSamples,
            stemWaveforms: [padded, padded, padded, padded]
        )
    }
}

// MARK: - StemFeatureSeriesTests

@Suite("Stem feature series (LFSTEM.1)")
struct StemFeatureSeriesTests {

    private static let sampleRate = 44_100
    private static let analysisHop = 1024

    /// Silence, then a loud 220 Hz tone starting exactly at `changeSecond`.
    private static func silenceThenTone(
        totalSeconds: Double, changeSecond: Double
    ) -> [Float] {
        let total = Int(totalSeconds * Double(sampleRate))
        let change = Int(changeSecond * Double(sampleRate))
        var out = [Float](repeating: 0, count: total)
        for i in change..<total {
            let t = Double(i - change) / Double(sampleRate)
            out[i] = Float(0.9 * sin(2 * Double.pi * 220 * t))
        }
        return out
    }

    private static func series(
        _ samples: [Float], windowSeconds: Double = 10.0, hopSeconds: Double = 2.0
    ) throws -> StemFeatureSeries {
        let separator = FixedWindowSeparator(
            windowSamples: Int(windowSeconds * Double(sampleRate)))
        return try SessionPreparer.analyzeStemSeries(
            samples: samples,
            sampleRate: sampleRate,
            separator: separator,
            analyzer: StemAnalyzer(sampleRate: Float(sampleRate)),
            hopSeconds: hopSeconds
        )
    }

    // MARK: - Alignment

    /// THE test. A change at a known second must appear at that second in the series.
    ///
    /// The tolerances are asymmetric on purpose. Before the change the bar is absolute — the
    /// series must carry NO energy, because the only way energy can appear early is if a
    /// separation window's content was filed under the wrong playback time. That is exactly
    /// what a window placed by its start rather than its end would do, and it would surface
    /// the tone up to 8 s early. After the change a little slack is allowed for the analyzer's
    /// own EMA smoothing, which is real and present in the live path too.
    @Test("A change at a known second lands at that second, and never earlier")
    func stemSeries_alignsTheChangeToItsPlaybackSecond() throws {
        let changeSecond = 5.0
        let samples = Self.silenceThenTone(totalSeconds: 12.0, changeSecond: changeSecond)
        let s = try Self.series(samples)

        #expect(!s.isEmpty, "series built")

        let quietCeiling: Float = 0.02
        var firstLoudSecond: Double?
        for (i, f) in s.frames.enumerated() {
            let second = Double(i) * s.hopSeconds
            if f.drumsEnergy > quietCeiling {
                firstLoudSecond = second
                break
            }
            #expect(second < changeSecond + 0.25,
                    "silence ran past the change second — the series is LATE or empty")
        }

        let firstLoud = try #require(firstLoudSecond, "the tone never appears in the series")
        #expect(firstLoud >= changeSecond - 0.05, """
                energy appears \(String(format: "%.2f", changeSecond - firstLoud)) s EARLY — a \
                separation window's content is filed under the wrong playback time
                """)
        #expect(firstLoud <= changeSecond + 0.20,
                "energy appears \(String(format: "%.2f", firstLoud - changeSecond)) s late")
    }

    /// The same claim through the public read path, which is what playback actually calls.
    @Test("sample(atPlaybackSeconds:) reads silence before the change and energy after")
    func sample_readsTheRightSideOfTheChange() throws {
        let samples = Self.silenceThenTone(totalSeconds: 12.0, changeSecond: 5.0)
        let s = try Self.series(samples)

        let before = try #require(s.sample(atPlaybackSeconds: 3.0))
        let after = try #require(s.sample(atPlaybackSeconds: 8.0))
        #expect(before.drumsEnergy <= 0.02, "3 s is inside the silent half")
        #expect(after.drumsEnergy > before.drumsEnergy,
                "8 s is inside the tone; energy must exceed the silent half")
    }

    // MARK: - Grid

    @Test("The grid is the live analysis hop, uniform, and covers the track")
    func stemSeries_gridIsUniformAndCoversTheTrack() throws {
        let totalSeconds = 12.0
        let samples = Self.silenceThenTone(totalSeconds: totalSeconds, changeSecond: 5.0)
        let s = try Self.series(samples)

        #expect(abs(s.hopSeconds - Double(Self.analysisHop) / Double(Self.sampleRate)) < 1e-9,
                "grid is the 1024-sample analysis hop, not the separation period")
        let expectedFrames = samples.count / Self.analysisHop
        #expect(abs(s.frames.count - expectedFrames) <= 1, """
                one frame per analysis hop across the file (got \(s.frames.count), \
                expected ~\(expectedFrames))
                """)
        #expect(abs(s.durationSeconds - totalSeconds) < 0.1, "series covers the track")
    }

    /// Frames must not be duplicated or dropped at span boundaries: `hopSamples` is not a whole
    /// number of analysis frames (88200 / 1024 = 86.13), so a loop that counts within each span
    /// instead of indexing the global grid drifts by a frame every few spans.
    @Test("Span boundaries do not drift: frame count matches the global grid exactly")
    func stemSeries_spanBoundariesDoNotDrift() throws {
        // 30 s at a 2 s hop = 15 spans, each 86.13 frames — enough for a per-span counter to
        // have accumulated ~2 frames of drift by the end.
        let samples = Self.silenceThenTone(totalSeconds: 30.0, changeSecond: 29.0)
        let s = try Self.series(samples)
        let expected = samples.count / Self.analysisHop
        #expect(abs(s.frames.count - expected) <= 1, """
                frame count drifted from the global grid (got \(s.frames.count), \
                expected \(expected)) — spans are being counted, not indexed
                """)
    }

    // MARK: - Edges

    @Test("Too little audio yields an empty series rather than a partial one")
    func stemSeries_emptyForTooShortAudio() throws {
        let s = try Self.series([Float](repeating: 0, count: 512))
        #expect(s.isEmpty)
    }

    @Test("Reads past the end clamp; reads on an empty series return nil")
    func sample_edges() throws {
        let samples = Self.silenceThenTone(totalSeconds: 12.0, changeSecond: 5.0)
        let s = try Self.series(samples)
        #expect(s.sample(atPlaybackSeconds: 9_999) == s.frames.last, """
                a clock that runs past the analysed length keeps the last frame, rather than \
                dropping stem coupling at the end of a track
                """)
        #expect(s.sample(atPlaybackSeconds: -1) == s.frames.first, "negative clamps to the start")
        #expect(StemFeatureSeries.empty.sample(atPlaybackSeconds: 1) == nil,
                "an empty series reports absence, so callers fall back to live separation")
    }
}
