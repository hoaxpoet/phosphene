// TapRecorder — plays an audio file and timestamps keypresses against its timeline.
//
// Timing model. `AVAudioPlayer.play(atTime:)` is scheduled against
// `deviceCurrentTime`, which shares the mach timebase with `CACurrentMediaTime()`
// on macOS. Scheduling a fixed lead therefore gives a deterministic origin, so a
// tap's position on the audio timeline is simply `CACurrentMediaTime() - origin`.
// That removes play() start-up jitter; what remains (audio output latency + human
// reaction time) is exactly what the calibration round measures and subtracts.
//
// The calibration metronome is rendered to a temp WAV and played through this SAME
// recorder — measuring the real path's latency rather than a synthetic one. Using a
// different playback route for calibration would calibrate away the wrong constant.

import Foundation
import AVFoundation
import QuartzCore

/// Collects tap timestamps from stdin in raw mode while audio plays.
/// `@unchecked Sendable` + NSLock: the reader thread appends, the main thread drains
/// (the codebase convention for a sync-callback type crossing threads).
final class TapRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var rawTaps: [Double] = []
    private var origin: Double = 0
    private var stopped = false

    /// Plays `url` and records taps until playback ends or `limitSeconds` elapses.
    /// Returns raw tap positions in seconds (NOT latency-corrected).
    func record(url: URL, limitSeconds: Double, prompt: String) throws -> [Double] {
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()

        let termios = RawMode()
        try termios.enable()
        defer { termios.restore() }

        startReaderThread()

        let lead = 0.35
        let start = player.deviceCurrentTime + lead
        lock.withLock { origin = start }
        guard player.play(atTime: start) else {
            throw TapCaptureError.playbackFailed(url.lastPathComponent)
        }

        // Countdown happens during the scheduling lead so the first beat isn't missed.
        FileHandle.standardError.write(Data("\n\(prompt)\n".utf8))

        let duration = limitSeconds > 0 ? min(limitSeconds, player.duration) : player.duration
        while true {
            let elapsed = CACurrentMediaTime() - start
            if elapsed >= duration { break }
            if lock.withLock({ stopped }) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        player.stop()

        return lock.withLock { rawTaps.sorted() }
    }

    // MARK: - stdin reader

    private func startReaderThread() {
        let thread = Thread { [weak self] in
            var byte: UInt8 = 0
            while read(STDIN_FILENO, &byte, 1) == 1 {
                let now = CACurrentMediaTime()
                guard let self else { return }
                // 'q' ends the pass early; anything else counts as a tap (space expected).
                if byte == UInt8(ascii: "q") {
                    self.lock.withLock { self.stopped = true }
                    return
                }
                self.lock.withLock {
                    let position = now - self.origin
                    if position >= 0 { self.rawTaps.append(position) }
                }
                FileHandle.standardError.write(Data(".".utf8))
            }
        }
        thread.stackSize = 64 * 1024
        thread.start()
    }
}

// MARK: - Terminal raw mode

/// Puts stdin in raw mode so single keypresses arrive immediately (no Enter, no echo).
final class RawMode {
    private var original = termios()
    private var enabled = false

    func enable() throws {
        guard isatty(STDIN_FILENO) == 1 else { throw TapCaptureError.notATerminal }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw TapCaptureError.terminalSetupFailed
        }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw TapCaptureError.terminalSetupFailed
        }
        enabled = true
    }

    func restore() {
        guard enabled else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        enabled = false
    }
}

// MARK: - Click track

enum ClickTrack {
    /// Renders a mono click track to a temp WAV. Clicks are a short decaying 1 kHz
    /// burst — a sharp transient so the tap target is unambiguous.
    static func render(bpm: Double, seconds: Double) throws -> (url: URL, clicks: [Double]) {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        ) else {
            throw TapCaptureError.clickTrackFailed
        }
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData else {
            throw TapCaptureError.clickTrackFailed
        }
        buffer.frameLength = frameCount

        let period = 60.0 / bpm
        let clickSamples = Int(sampleRate * 0.015)
        var clicks: [Double] = []
        var clickTime = 0.5  // half-second lead-in before the first click
        while clickTime + 0.015 < seconds {
            clicks.append(clickTime)
            let startFrame = Int(clickTime * sampleRate)
            for i in 0..<clickSamples where startFrame + i < Int(frameCount) {
                let phase = Double(i) / sampleRate
                let envelope = exp(-phase * 260.0)
                let value = sin(2.0 * .pi * 1_000.0 * phase) * envelope * 0.7
                channel[0][startFrame + i] = Float(value)
            }
            clickTime += period
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beatbench_calibration_\(Int(bpm)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return (url, clicks)
    }
}

// MARK: - Errors

enum TapCaptureError: Error, CustomStringConvertible {
    case notATerminal
    case terminalSetupFailed
    case playbackFailed(String)
    case clickTrackFailed
    case fixtureMissing(String)
    case unknownTrack(String)

    var description: String {
        switch self {
        case .notATerminal:
            return "stdin is not a terminal — run TapCapture directly in Terminal, not through a pipe."
        case .terminalSetupFailed:
            return "could not put the terminal in raw mode"
        case .playbackFailed(let name):
            return "playback failed for \(name)"
        case .clickTrackFailed:
            return "could not render the calibration click track"
        case .fixtureMissing(let path):
            return "fixture not found: \(path) — run Scripts/beatbench_copy_fixtures.sh"
        case .unknownTrack(let id):
            return "no track '\(id)' in the BeatBench manifest"
        }
    }
}
