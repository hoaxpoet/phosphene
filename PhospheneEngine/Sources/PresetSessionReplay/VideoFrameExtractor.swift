// VideoFrameExtractor.swift — Extract individual frames from session video.
//
// Wraps `ffmpeg -ss <time> -i <video> -frames:v 1 -f image2 <out>` for each
// requested timestamp. ffmpeg must be on PATH.
//
// Two extraction modes:
//   - byTimestamp(seconds:): extracts a single frame at the given wallclock
//     time (used for audio-event evidence).
//   - uniformGrid(count:): extracts N frames evenly spaced across the video
//     (used for motion-band analysis).
//
// Extracted images are written to a caller-provided output directory.

import Foundation

public enum VideoFrameExtractorError: Error, CustomStringConvertible {
    case ffmpegMissing
    case ffmpegFailed(stderr: String, exitCode: Int32)
    case noVideoInSession

    public var description: String {
        switch self {
        case .ffmpegMissing: return "ffmpeg not found on PATH. brew install ffmpeg."
        case .ffmpegFailed(let stderr, let exit): return "ffmpeg failed (exit \(exit)): \(stderr)"
        case .noVideoInSession: return "Session has no video.mp4; cannot extract frames."
        }
    }
}

public enum VideoFrameExtractor {

    /// Extract one frame at `seconds` from `video`, write to `output`.
    /// Returns the resolved output URL on success.
    public static func extractFrame(
        from video: URL,
        atSeconds seconds: Double,
        to output: URL,
        targetWidth: Int = 960
    ) throws -> URL {
        guard let ffmpeg = locateFfmpeg() else {
            throw VideoFrameExtractorError.ffmpegMissing
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // Use `-ss` after `-i` for accurate seeking; `-ss` before `-i` is faster
        // but less precise. We need accuracy for audio-event-aligned frames.
        let process = Process()
        process.launchPath = ffmpeg
        process.arguments = [
            "-y",
            "-i", video.path,
            "-ss", String(seconds),
            "-frames:v", "1",
            "-vf", "scale=\(targetWidth):-1",
            "-q:v", "2",
            output.path
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()  // discard

        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "<no stderr>"
            throw VideoFrameExtractorError.ffmpegFailed(
                stderr: msg, exitCode: process.terminationStatus)
        }
        return output
    }

    /// Extract `count` frames evenly spaced across `video`, write to `outputDir`.
    /// Returns the URLs of the written frames (chronological order).
    public static func extractUniformGrid(
        from video: URL,
        count: Int,
        to outputDir: URL,
        targetWidth: Int = 960
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let duration = try probeDuration(video: video)
        // Back off the last sample slightly — ffmpeg fails extracting at exact
        // EOF. Sample over [0, duration - 0.05] so even with rounding the last
        // request stays in-frame.
        let span = max(duration - 0.05, 0)
        var urls: [URL] = []
        for idx in 0..<count {
            let timeOffset = span * Double(idx) / Double(max(count - 1, 1))
            let outURL = outputDir.appendingPathComponent(String(format: "grid_%03d.png", idx))
            _ = try extractFrame(from: video, atSeconds: timeOffset, to: outURL, targetWidth: targetWidth)
            urls.append(outURL)
        }
        return urls
    }

    // MARK: - Internal

    private static func locateFfmpeg() -> String? {
        // PATH lookup via /usr/bin/env
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stdout.isEmpty ? nil : stdout
    }

    private static func probeDuration(video: URL) throws -> Double {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = [
            "ffprobe",
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            video.path
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw VideoFrameExtractorError.ffmpegFailed(
                stderr: stderr, exitCode: process.terminationStatus)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let durationStr = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Double(durationStr) ?? 0
    }
}
