// SoakTestHarness+AudioGen — Procedural audio fixture generation (Increment 7.1).
//
// Generates a 10-second synthetic audio file to drive the soak harness when no
// real audio file is provided. Avoids a fixture file in the repo. D-060(e).

import Foundation
import AVFoundation
import os.log

// MARK: - Synthetic Audio Generation

@available(macOS 14.2, *)
extension SoakTestHarness {

    /// Generate a 10-second procedural audio fixture: sine sweep (100→4000 Hz) + light
    /// noise + kick pulses at 120 BPM. Written to a temp `.caf` file; the caller owns the URL.
    public static func generateSyntheticAudioFile() throws -> URL {
        let sampleRate: Double = 44100
        let durationSecs = 10
        let frameCount = AVAudioFrameCount(sampleRate * Double(durationSecs))

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw SoakError.audioGenerationFailed("Could not create AVAudioFormat")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SoakError.audioGenerationFailed("Could not allocate AVAudioPCMBuffer")
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else {
            throw SoakError.audioGenerationFailed("No float channel data")
        }

        let total = Int(frameCount)
        let fs = Float(sampleRate)

        for idx in 0..<total {
            let sampleTime = Float(idx) / fs

            // Sine sweep 100 → 4000 Hz over 10 s.
            let freq = 100.0 + (4000.0 - 100.0) * sampleTime / 10.0
            let phase = 2 * Float.pi * freq * sampleTime
            var sample = 0.3 * sin(phase)

            // Light noise at −40 dBFS.
            sample += Float.random(in: -0.01...0.01)

            // Kick transients at 120 BPM (every 0.5 s): cosine + exponential decay.
            let kickPhase = sampleTime.truncatingRemainder(dividingBy: 0.5)
            if kickPhase < 0.08 {
                let decay = exp(-kickPhase * 30.0)
                sample += 0.5 * decay * cos(2 * Float.pi * 60.0 * kickPhase)
            }

            samples[idx] = sample
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene_soak_loop_\(Int(Date().timeIntervalSince1970)).caf")

        let outFile = try AVAudioFile(forWriting: tempURL,
                                     settings: format.settings,
                                     commonFormat: .pcmFormatFloat32,
                                     interleaved: false)
        try outFile.write(from: buffer)

        logger.info("Soak: generated synthetic audio: \(tempURL.lastPathComponent)")
        return tempURL
    }
}

// MARK: - Error

public enum SoakError: Error {
    case audioGenerationFailed(String)
}
