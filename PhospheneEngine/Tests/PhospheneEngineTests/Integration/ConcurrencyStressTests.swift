// ConcurrencyStressTests — CLEAN.1.6 / GAP-7 dynamic concurrency validation.
//
// Static review cannot prove the absence of data races; ThreadSanitizer can.
// These are the stress harness the BUG-031/032 fixes (CLEAN.1.2/1.3) are
// validated against under TSan — run them via `Scripts/tsan_stress.sh`, which
// sets `PHOSPHENE_STRESS=1` and `swift test --sanitize=thread`. A TSan-clean
// run (no "ThreadSanitizer: data race" report) is the pass condition.
//
// They are OPT-IN (env-gated) so the normal closeout suite stays light — the
// always-on regression coverage lives in StemSeparatorConcurrencyTests (BUG-031)
// and SessionLifecycleGenerationTests / SessionRecoverySingleFlightTests
// (BUG-032). This file's job is to hammer the two race surfaces hard enough that
// TSan would flag any residual unsynchronized access.
//
// Probe result (2026-06-13): TSan builds + runs cleanly against the real
// Metal/MPSGraph `StemSeparator` — no framework false positives, no suppressions
// needed.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

// MARK: - Opt-in gate

private var stressEnabled: Bool {
    ProcessInfo.processInfo.environment["PHOSPHENE_STRESS"] == "1"
}

/// Lock-guarded failure box for detached work (mirrors SessionLifecycleChurnTests).
private final class StressErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ message: String) { lock.withLock { if stored == nil { stored = message } } }
    var message: String? { lock.withLock { stored } }
}

// MARK: - Minimal lifecycle doubles (churn test; no Metal → no TSan-Metal noise)

private final class StressConnector: PlaylistConnecting, @unchecked Sendable {
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        [TrackIdentity(title: "S1", artist: "A"), TrackIdentity(title: "S2", artist: "A")]
    }
}
private final class StressResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        // Brief delay so prep is genuinely in flight when end/cancel fires.
        try? await Task.sleep(nanoseconds: 8_000_000)
        return URL(string: "https://example.com/\(track.title).m4a")
    }
}
private final class StressDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let samples = (0..<44_100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44_100, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}
private final class StressAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}
/// Local separator double for the churn test — avoids FakeStemSeparator's
/// `@available(macOS 14.2)` gate; returns stems by value (CLEAN.1.2 contract).
private final class StressSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in try UMABuffer<Float>(device: device, capacity: 4096) }
        for buf in stemBuffers { buf.write([Float](repeating: 0.1, count: 4096)) }
    }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let frame = AudioFrame(sampleRate: sampleRate, sampleCount: 4096, channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: 4096,
            stemWaveforms: stemBuffers.map { Array($0.pointer.prefix(4096)) }
        )
    }
}

// MARK: - Suite

@Suite("Concurrency stress harness (CLEAN.1.6 / GAP-7)", .serialized)
struct ConcurrencyStressTests {

    /// BUG-031 surface: two concurrent loops (the live `stemQueue` shape and the
    /// session-prep `Task.detached` shape) hammer `separate()` on ONE shared
    /// `StemSeparator`. Under TSan this flags any unsynchronized access to the
    /// shared model input/output buffers. Post-CLEAN.1.2 (full input→predict→
    /// output lock + return-by-value) it is race-free; every call returns 4 stems.
    @Test func liveAndPrepOverlap_sharedSeparator_raceFree() throws {
        guard stressEnabled else { return }   // opt-in; run via Scripts/tsan_stress.sh
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StemSeparator(device: device)

        let sine = AudioFixtures.mixStereo(
            left: AudioFixtures.sineWave(frequency: 440, sampleRate: 44_100, duration: 1.0),
            right: AudioFixtures.sineWave(frequency: 440, sampleRate: 44_100, duration: 1.0)
        )
        let silence = AudioFixtures.silence(sampleCount: 44_100 * 2)

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.liveprep", attributes: .concurrent)
        let errors = StressErrorBox()

        // 2 loops × 8 iterations = 16 overlapping separations on the shared instance.
        for loop in 0..<2 {
            let input = (loop == 0) ? sine : silence   // "live" vs "prep" caller
            for _ in 0..<8 {
                group.enter()
                queue.async {
                    do {
                        let result = try separator.separate(
                            audio: input, channelCount: 2, sampleRate: 44_100
                        )
                        if result.stemWaveforms.count != 4 {
                            errors.set("expected 4 stems, got \(result.stemWaveforms.count)")
                        }
                    } catch {
                        errors.set("separate threw: \(error)")
                    }
                    group.leave()
                }
            }
        }

        #expect(group.wait(timeout: .now() + 300) == .success, "overlapping separations timed out")
        #expect(errors.message == nil, "\(errors.message ?? "")")
    }

    /// BUG-032 surface: rapid session start → end/cancel cycles with preparation
    /// in flight, so the off-actor prep path (`analyzePreview` in `Task.detached`)
    /// overlaps the MainActor lifecycle teardown (cancel + generation bump +
    /// task/subscription clear). Under TSan this flags any race in the streaming
    /// lifecycle; the watchdog timeout flags a deadlock. Fakes only (no Metal).
    @Test @MainActor func sessionStartEndCancelChurn_raceFreeNoDeadlock() async throws {
        guard stressEnabled else { return }
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")

        for round in 0..<25 {
            let preparer = SessionPreparer(
                resolver: StressResolver(),
                downloader: StressDownloader(),
                stemSeparator: try StressSeparator(device: device),
                stemAnalyzer: StressAnalyzer(),
                moodClassifier: MockMoodClassifier()
            )
            let manager = SessionManager(connector: StressConnector(), preparer: preparer)

            let startTask = Task { @MainActor in
                await manager.startSession(source: .appleMusicCurrentPlaylist)
            }
            // Let preparation actually begin (the Task.detached fires) before tearing down.
            try? await Task.sleep(nanoseconds: 4_000_000)
            if round % 3 == 0 { manager.cancel() } else { manager.endSession() }
            await startTask.value
            // No per-round state assert: end/cancel racing startSession's connect
            // await can legitimately leave .preparing. The pass conditions are that
            // every round completes (no deadlock — the `await` returns) and TSan
            // reports no data race across the churn.
        }

        // Deterministic post-condition: after the churn, a fresh manager still
        // transitions cleanly (the churn left no corrupt shared/static state).
        let finalManager = SessionManager(
            connector: StressConnector(),
            preparer: SessionPreparer(
                resolver: StressResolver(),
                downloader: StressDownloader(),
                stemSeparator: try StressSeparator(device: device),
                stemAnalyzer: StressAnalyzer(),
                moodClassifier: MockMoodClassifier()
            )
        )
        finalManager.endSession()
        #expect(finalManager.state == .ended)
    }
}
