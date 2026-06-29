// PrepPrefetchTests — PREPPERF.2 ①: the prep pipeline prefetches the network half
// (resolve + download) ahead of the serial analysis cursor. These guard the two
// behaviours that define the refactor:
//   1. Downloads actually overlap (a serial pipeline would run them one at a time).
//   2. Analysis is consumed in strict playlist order even when downloads finish
//      out of order (the StemSeparator stays serial; cachedTracks order is stable).

import Metal
import XCTest
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

// MARK: - Doubles

private func makePreview(_ track: TrackIdentity, samples: Int = 44_100) -> PreviewAudio {
    var pcm = [Float](repeating: 0, count: samples)
    for i in 0..<samples { pcm[i] = 0.05 * sin(2.0 * .pi * 440.0 * Float(i) / 44_100.0) }
    return PreviewAudio(trackIdentity: track, pcmSamples: pcm, sampleRate: 44_100, duration: 1.0)
}

private final class FixedResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/preview.m4a")
    }
}

/// Records the peak number of concurrently in-flight downloads. Each download
/// holds for `delayNs` so overlap is observable.
private final class OverlapDownloader: PreviewDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var peakInFlight = 0
    let delayNs: UInt64
    init(delayNs: UInt64) { self.delayNs = delayNs }

    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        lock.withLock { inFlight += 1; peakInFlight = max(peakInFlight, inFlight) }
        try? await Task.sleep(nanoseconds: delayNs)
        lock.withLock { inFlight -= 1 }
        return makePreview(track)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

/// Track with title "T0" downloads slowly; everything else returns immediately —
/// so downloads finish out of playlist order.
private final class SlowFirstDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        if track.title == "T0" { try? await Task.sleep(nanoseconds: 120_000_000) }
        return makePreview(track)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class FixedAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures {
        StemFeatures(
            vocalsEnergy: 0.3, vocalsBand0: 0.2, vocalsBand1: 0.1, vocalsBeat: 0,
            drumsEnergy: 0.5, drumsBand0: 0.4, drumsBand1: 0.3, drumsBeat: 0.1,
            bassEnergy: 0.4, bassBand0: 0.3, bassBand1: 0.2, bassBeat: 0,
            otherEnergy: 0.2, otherBand0: 0.1, otherBand1: 0.05, otherBeat: 0
        )
    }
    func reset() {}
}

private func makeTrack(_ title: String) -> TrackIdentity {
    TrackIdentity(title: title, artist: "Artist")
}

@available(macOS 14.2, *)
@MainActor
final class PrepPrefetchTests: XCTestCase {

    private func makePreparer(
        resolver: any PreviewResolving,
        downloader: any PreviewDownloading,
        separator: any StemSeparating
    ) -> SessionPreparer {
        SessionPreparer(
            resolver: resolver,
            downloader: downloader,
            stemSeparator: separator,
            stemAnalyzer: FixedAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )
    }

    /// Downloads run concurrently (peak in-flight > 1). A serial pipeline would hold
    /// peak at 1 — so this fails on the pre-PREPPERF.2 code.
    func testPrefetchOverlapsDownloads() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let separator = try FakeStemSeparator(device: device)
        let downloader = OverlapDownloader(delayNs: 40_000_000)
        let preparer = makePreparer(resolver: FixedResolver(), downloader: downloader, separator: separator)
        let tracks = (0..<4).map { makeTrack("T\($0)") }

        let result = await preparer.prepare(tracks: tracks)

        XCTAssertEqual(result.cachedTracks.count, 4)
        XCTAssertGreaterThanOrEqual(
            downloader.peakInFlight, 2,
            "prefetch should run downloads concurrently; got peak \(downloader.peakInFlight)"
        )
    }

    /// Even when track 0's download is the slowest, analysis is consumed in playlist
    /// order — cachedTracks stays [T0, T1, T2, T3], not download-completion order.
    func testAnalysisStaysInPlaylistOrderDespiteOutOfOrderDownloads() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let separator = try FakeStemSeparator(device: device)
        let preparer = makePreparer(resolver: FixedResolver(), downloader: SlowFirstDownloader(), separator: separator)
        let tracks = (0..<4).map { makeTrack("T\($0)") }

        let result = await preparer.prepare(tracks: tracks)

        XCTAssertEqual(result.cachedTracks, tracks, "analysis must complete in playlist order")
    }
}
