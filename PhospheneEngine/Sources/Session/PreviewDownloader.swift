// PreviewDownloader — Downloads AAC/MP3 preview clips and decodes them to PCM.
// Batch processing with configurable concurrency (default 4 parallel downloads).
// Failed individual downloads are skipped so the batch always completes.

import Foundation
import AVFoundation
import os

// MARK: - Protocol

/// Downloads preview audio for a track and decodes it to raw PCM.
public protocol PreviewDownloading: Sendable {
    /// Download the preview at `url` and decode it to `PreviewAudio`.
    /// Returns `nil` if download or decode fails.
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio?

    /// Download previews for multiple tracks concurrently.
    /// Tracks whose downloads fail are silently skipped.
    /// Result order matches the order of `tracks`.
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio]
}

// MARK: - Concrete Implementation

/// Downloads preview clips and decodes them to mono Float32 PCM via `AVAudioFile`.
///
/// The download step is injectable so tests never touch the network.
/// Decoded audio is always mono (stereo sources are averaged) and
/// resampled to the file's native sample rate (typically 44100 Hz for
/// iTunes previews).
///
/// Temp files are written to `tempDirectoryURL` and deleted immediately after
/// decoding, regardless of success or failure.
public final class PreviewDownloader: PreviewDownloading, @unchecked Sendable {

    // MARK: - Dependencies

    /// Injectable data fetcher. Receives the remote URL and returns raw audio data.
    /// Defaults to `URLSession.shared`. Replace in tests to avoid real network I/O.
    public var fileFetcher: (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    // MARK: - Configuration

    /// Maximum number of concurrent downloads in `batchDownload`. Defaults to 4.
    public let concurrency: Int

    /// Directory used for temporary audio files during decode. Defaults to the
    /// system temp directory. Override in tests to verify cleanup behaviour.
    public var tempDirectoryURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Init

    /// Create a downloader.
    /// - Parameter concurrency: Max parallel downloads in `batchDownload`. Default 4.
    public init(concurrency: Int = 4) {
        self.concurrency = concurrency
    }

    // MARK: - PreviewDownloading

    public func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let data: Data
        do {
            data = try await fileFetcher(url)
        } catch {
            logger.error("Download failed for '\(track.title)': \(error)")
            return nil
        }

        do {
            return try decodeAudio(data: data, track: track)
        } catch {
            logger.error("Decode failed for '\(track.title)': \(error)")
            return nil
        }
    }

    public func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] {
        var results: [PreviewAudio?] = Array(repeating: nil, count: tracks.count)

        await withTaskGroup(of: (Int, PreviewAudio?).self) { group in
            var nextIndex = 0
            var inFlight = 0

            // Seed initial batch up to concurrency limit.
            while nextIndex < tracks.count && inFlight < concurrency {
                let idx = nextIndex
                let (track, url) = tracks[idx]
                group.addTask { [weak self] in
                    guard let self else { return (idx, nil) }
                    return (idx, await self.download(track: track, from: url))
                }
                nextIndex += 1
                inFlight += 1
            }

            // As each task finishes, dispatch the next pending track.
            for await (idx, audio) in group {
                results[idx] = audio
                inFlight -= 1

                if nextIndex < tracks.count {
                    let next = nextIndex
                    let (track, url) = tracks[next]
                    group.addTask { [weak self] in
                        guard let self else { return (next, nil) }
                        return (next, await self.download(track: track, from: url))
                    }
                    nextIndex += 1
                    inFlight += 1
                }
            }
        }

        return results.compactMap { $0 }
    }

    // MARK: - Private

    private func decodeAudio(data: Data, track: TrackIdentity) throws -> PreviewAudio? {
        let ext = audioFileExtension(for: data)
        let tempURL = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = try AVAudioFile(forReading: tempURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        try file.read(into: buffer)

        let actualFrames = Int(buffer.frameLength)
        guard actualFrames > 0, let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        var samples: [Float]
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: actualFrames))
        } else {
            // Average all channels to mono.
            samples = [Float](repeating: 0, count: actualFrames)
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                let ptr = UnsafeBufferPointer(start: channelData[ch], count: actualFrames)
                for i in 0..<actualFrames {
                    samples[i] += ptr[i] * scale
                }
            }
        }

        let sampleRate = Int(format.sampleRate)
        let duration = TimeInterval(actualFrames) / format.sampleRate

        return PreviewAudio(
            trackIdentity: track,
            pcmSamples: samples,
            sampleRate: sampleRate,
            duration: duration
        )
    }

    /// Detect the audio container format from the first bytes of the data.
    private func audioFileExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "m4a" }

        // WAV: "RIFF"
        if data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 {
            return "wav"
        }
        // AIFF / AIFF-C: "FORM"
        if data[0] == 0x46 && data[1] == 0x4F && data[2] == 0x52 && data[3] == 0x4D {
            return "aiff"
        }
        // CAF: "caff"
        if data[0] == 0x63 && data[1] == 0x61 && data[2] == 0x66 && data[3] == 0x66 {
            return "caf"
        }
        // MP3: ID3 tag header
        if data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 {
            return "mp3"
        }
        // MP3: sync word
        if data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
            return "mp3"
        }
        // Default: AAC/M4A (iTunes preview format)
        return "m4a"
    }
}

// MARK: - Logger

private let logger = Logger(subsystem: "com.phosphene", category: "PreviewDownloader")
