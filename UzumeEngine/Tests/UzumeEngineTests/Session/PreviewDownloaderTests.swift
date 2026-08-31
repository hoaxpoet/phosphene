// PreviewDownloaderTests — Unit tests for PreviewDownloader.
// Download step injected via fileFetcher. Decode step uses real AVAudioFile
// with synthetic WAV data generated in-test.

import Testing
import Foundation
import AVFoundation
@testable import Session

// MARK: - WAV Generator

/// Generate a minimal WAV file in memory at the given sample rate and duration.
/// Uses a 440 Hz sine wave at -12 dBFS to produce non-zero, non-clipping signal.
private func makeSineWAV(sampleRate: Int = 44100, durationSeconds: Double = 30.0) -> Data {
    let sampleCount = Int(Double(sampleRate) * durationSeconds)
    var samples = [Int16](repeating: 0, count: sampleCount)
    let amplitude: Double = 16383  // ~-6 dBFS, well below Int16.max
    for i in 0..<sampleCount {
        let phase = 2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate)
        samples[i] = Int16(amplitude * sin(phase))
    }

    let dataSize = sampleCount * 2  // 16-bit mono = 2 bytes per sample
    let headerSize = 44

    var data = Data(count: headerSize + dataSize)
    data.withUnsafeMutableBytes { ptr in
        // RIFF header
        ptr.storeBytes(of: 0x46464952, toByteOffset: 0, as: UInt32.self)  // "RIFF"
        ptr.storeBytes(of: UInt32(36 + dataSize), toByteOffset: 4, as: UInt32.self)
        ptr.storeBytes(of: 0x45564157, toByteOffset: 8, as: UInt32.self)  // "WAVE"
        // fmt chunk
        ptr.storeBytes(of: 0x20746D66, toByteOffset: 12, as: UInt32.self)  // "fmt "
        ptr.storeBytes(of: UInt32(16), toByteOffset: 16, as: UInt32.self)   // chunk size
        ptr.storeBytes(of: UInt16(1), toByteOffset: 20, as: UInt16.self)    // PCM
        ptr.storeBytes(of: UInt16(1), toByteOffset: 22, as: UInt16.self)    // mono
        ptr.storeBytes(of: UInt32(sampleRate), toByteOffset: 24, as: UInt32.self)
        ptr.storeBytes(of: UInt32(sampleRate * 2), toByteOffset: 28, as: UInt32.self) // byte rate
        ptr.storeBytes(of: UInt16(2), toByteOffset: 32, as: UInt16.self)    // block align
        ptr.storeBytes(of: UInt16(16), toByteOffset: 34, as: UInt16.self)   // bits per sample
        // data chunk
        ptr.storeBytes(of: 0x61746164, toByteOffset: 36, as: UInt32.self)  // "data"
        ptr.storeBytes(of: UInt32(dataSize), toByteOffset: 40, as: UInt32.self)
    }

    // Write samples (little-endian)
    for (i, sample) in samples.enumerated() {
        let offset = headerSize + i * 2
        data[offset] = UInt8(truncatingIfNeeded: sample)
        data[offset + 1] = UInt8(truncatingIfNeeded: sample >> 8)
    }

    return data
}

// MARK: - Helpers

private func makeTrack(_ title: String = "Test Track") -> TrackIdentity {
    TrackIdentity(title: title, artist: "Test Artist")
}

private func makeDownloader(concurrency: Int = 4) -> PreviewDownloader {
    PreviewDownloader(concurrency: concurrency)
}

// MARK: - Suite

@Suite("PreviewDownloader")
struct PreviewDownloaderTests {

    // MARK: - PCM Output

    @Test func downloadAndDecode_producesNonZeroPCM() async throws {
        let downloader = makeDownloader()
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 1.0)

        downloader.fileFetcher = { _ in wavData }

        let result = await downloader.download(
            track: makeTrack(),
            from: URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        )

        let audio = try #require(result)
        #expect(!audio.pcmSamples.isEmpty)

        // At least some samples must be non-zero (440 Hz sine wave).
        let nonZero = audio.pcmSamples.filter { abs($0) > 0.001 }
        #expect(!nonZero.isEmpty)
    }

    // MARK: - Sample Rate

    @Test func downloadedAudio_sampleRate_is44100() async throws {
        let downloader = makeDownloader()
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 1.0)

        downloader.fileFetcher = { _ in wavData }

        let result = await downloader.download(
            track: makeTrack(),
            from: URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        )

        let audio = try #require(result)
        #expect(audio.sampleRate == 44100)
    }

    // MARK: - Duration

    @Test func downloadedAudio_duration_approximately30s() async throws {
        let downloader = makeDownloader()
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 30.0)

        downloader.fileFetcher = { _ in wavData }

        let result = await downloader.download(
            track: makeTrack(),
            from: URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        )

        let audio = try #require(result)
        // Allow ±0.1s tolerance for floating-point frame count conversion.
        #expect(audio.duration >= 29.9 && audio.duration <= 30.1)
    }

    // MARK: - Concurrency Limit

    @Test func batchDownload_respectsConcurrencyLimit() async throws {
        let limit = 2
        let downloader = makeDownloader(concurrency: limit)
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 0.1)

        let counterLock = NSLock()
        var currentConcurrent = 0
        var maxObservedConcurrent = 0

        downloader.fileFetcher = { _ in
            counterLock.withLock {
                currentConcurrent += 1
                maxObservedConcurrent = max(maxObservedConcurrent, currentConcurrent)
            }
            // Simulate async work so concurrency is observable.
            try await Task.sleep(nanoseconds: 20_000_000)  // 20ms
            counterLock.withLock { currentConcurrent -= 1 }
            return wavData
        }

        let url = URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        let tracks = (0..<6).map { i -> (TrackIdentity, URL) in
            (makeTrack("Track \(i)"), url)
        }

        let results = await downloader.batchDownload(tracks: tracks)

        #expect(results.count == 6)
        #expect(maxObservedConcurrent <= limit)
    }

    // MARK: - Failure Resilience

    @Test func failedDownload_skipsTrack_continuesBatch() async throws {
        let downloader = makeDownloader()
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 1.0)

        let url = URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        let failURL = URL(string: "https://example.com/fail.m4a")!  // swiftlint:disable:this force_unwrapping

        downloader.fileFetcher = { requestURL in
            if requestURL == failURL {
                throw URLError(.badServerResponse)
            }
            return wavData
        }

        let tracks: [(TrackIdentity, URL)] = [
            (makeTrack("Good A"), url),
            (makeTrack("Bad"), failURL),
            (makeTrack("Good B"), url)
        ]

        let results = await downloader.batchDownload(tracks: tracks)

        // The failed track is skipped; the two good tracks decode successfully.
        #expect(results.count == 2)
        #expect(results[0].trackIdentity.title == "Good A")
        #expect(results[1].trackIdentity.title == "Good B")
    }

    // MARK: - Temp File Cleanup

    @Test func tempFiles_cleanedUpAfterDecode() async throws {
        let downloader = makeDownloader()
        let wavData = makeSineWAV(sampleRate: 44100, durationSeconds: 1.0)

        // Point the downloader at a dedicated temp subdirectory we control.
        let testTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewDownloaderCleanupTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testTempDir, withIntermediateDirectories: true)
        downloader.tempDirectoryURL = testTempDir
        defer { try? FileManager.default.removeItem(at: testTempDir) }

        downloader.fileFetcher = { _ in wavData }

        _ = await downloader.download(
            track: makeTrack(),
            from: URL(string: "https://example.com/preview.m4a")!  // swiftlint:disable:this force_unwrapping
        )

        // The temp dir should be empty — decode cleans up after itself.
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: testTempDir.path)) ?? []
        #expect(remaining.isEmpty)
    }
}
