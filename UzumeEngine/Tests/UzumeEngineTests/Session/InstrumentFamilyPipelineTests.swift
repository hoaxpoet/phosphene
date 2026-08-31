// InstrumentFamilyPipelineTests — IFC.4 (D-177) pipeline integration.
//
// Proves the analyzePreview wiring: the injected InstrumentFamilyAnalyzing is
// invoked over the preview PCM and its per-window series lands on
// CachedTrackData.instrumentFamilySeries. Uses a stub family analyzer (no PANNs
// / Metal weights) so it runs in any environment; the stem/MIR stages run on
// synthetic PCM. The real per-family firing on an orchestral clip is dev-local
// evidence (no committed orchestral fixture), mirroring IFC.2's parity setup.

import Foundation
import Metal
import Testing
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

@Suite struct InstrumentFamilyPipelineTests {

    /// Returns a fixed series and records that it was asked for the preview PCM.
    final class StubFamilyAnalyzer: InstrumentFamilyAnalyzing, @unchecked Sendable {
        let series: [InstrumentFamilyActivity]
        private(set) var lastSampleCount = 0
        init(series: [InstrumentFamilyActivity]) { self.series = series }
        func analyzeFamilyActivity(samples: [Float], sampleRate: Double) -> [InstrumentFamilyActivity] {
            lastSampleCount = samples.count
            return series
        }
    }

    static func window(_ v: Float) -> InstrumentFamilyActivity {
        InstrumentFamilyActivity(raw: [v, v, v, v], smoothed: [v, v, v, v],
                                 rel: [0, 0, 0, 0], dev: [v, v, v, v])
    }

    @Test func test_analyzePreview_populatesFamilySeriesFromAnalyzer() throws {
        // FakeStemSeparator requires macOS 14.2; the deployment floor is 14.0.
        guard #available(macOS 14.2, *) else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device (headless CI) — the family wiring is identical with
            // or without a device; the stub-vs-CachedTrackData seam is covered by
            // the in-memory checks below once a device is present.
            return
        }
        let sampleRate = 44_100
        // 2 s of silence is enough for the stem/MIR stages to run without crashing;
        // the stub family analyzer ignores the PCM content.
        let pcm = [Float](repeating: 0, count: sampleRate * 2)
        let preview = PreviewAudio(
            trackIdentity: TrackIdentity(title: "t", artist: "a", spotifyID: "test:ifc4"),
            pcmSamples: pcm, sampleRate: sampleRate, duration: 2.0)

        let stub = StubFamilyAnalyzer(series: [Self.window(0.1), Self.window(0.2), Self.window(0.3)])
        let separator = try FakeStemSeparator(device: device, bufferCapacity: pcm.count)
        let analyzer = StemAnalyzer(sampleRate: Float(sampleRate))
        let classifier = MockMoodClassifier()

        let cached = try SessionPreparer.analyzePreview(
            preview,
            separator: separator,
            analyzer: analyzer,
            classifier: classifier,
            beatGridAnalyzer: nil,
            familyAnalyzer: stub,
            prefetchedProfile: nil)

        #expect(stub.lastSampleCount == pcm.count, "analyzer ran over the preview PCM")
        #expect(cached.instrumentFamilySeries.count == 3, "series lands on CachedTrackData")
        #expect(cached.instrumentFamilySeries[1].smoothed[0] == 0.2)
    }

    @Test func test_analyzePreview_nilAnalyzerYieldsEmptySeries() throws {
        guard #available(macOS 14.2, *) else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let sampleRate = 44_100
        let pcm = [Float](repeating: 0, count: sampleRate * 2)
        let preview = PreviewAudio(
            trackIdentity: TrackIdentity(title: "t", artist: "a", spotifyID: "test:ifc4-nil"),
            pcmSamples: pcm, sampleRate: sampleRate, duration: 2.0)
        let separator = try FakeStemSeparator(device: device, bufferCapacity: pcm.count)

        let cached = try SessionPreparer.analyzePreview(
            preview,
            separator: separator,
            analyzer: StemAnalyzer(sampleRate: Float(sampleRate)),
            classifier: MockMoodClassifier(),
            familyAnalyzer: nil)

        #expect(cached.instrumentFamilySeries.isEmpty, "no analyzer → empty series (backward compat)")
    }
}
