import Foundation

extension SessionRecorder {

    // MARK: - Public API: Stem Separation

    /// Dump the four separated stem waveforms as 16-bit PCM WAV files.
    public func recordStemSeparation(
        stemWaveforms: [[Float]],
        sampleRate: Int,
        trackTitle: String?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard stemWaveforms.count >= 4 else { return }
            let names = ["drums", "bass", "vocals", "other"]
            let idx = self.stemDumpIndex
            self.stemDumpIndex += 1
            let safeTitle = (trackTitle ?? "unknown")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .prefix(60)
            let dumpDir = self.sessionDir
                .appendingPathComponent("stems", isDirectory: true)
                .appendingPathComponent(String(format: "%04d_%@", idx, String(safeTitle)),
                                        isDirectory: true)
            try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
            for (i, waveform) in stemWaveforms.prefix(4).enumerated() {
                let url = dumpDir.appendingPathComponent("\(names[i]).wav")
                SessionRecorder.writeWav(samples: waveform, sampleRate: sampleRate, to: url)
            }
            self.writeLogLine("stem separation \(idx) "
                              + "(\(stemWaveforms[0].count) samples) "
                              + "track=\(safeTitle) → \(dumpDir.lastPathComponent)")
        }
    }
}
