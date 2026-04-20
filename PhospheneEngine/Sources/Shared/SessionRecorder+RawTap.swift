import Foundation
import os.log

private let rawTapLogger = Logger(subsystem: "com.phosphene", category: "SessionRecorder")

extension SessionRecorder {

    // MARK: - Raw tap diagnostic capture

    /// Copy the most recent Core Audio tap samples into the raw_tap.wav
    /// diagnostic file.  Safe to call from the IO proc — heavy I/O is
    /// dispatched onto the recorder queue.  Automatically stops after
    /// `rawTapDurationSeconds` of audio to cap file size.
    public func recordRawTapSamples(
        pointer: UnsafePointer<Float>,
        count: Int,
        sampleRate: Float,
        channelCount: UInt32
    ) {
        guard count > 0 else { return }
        let byteCount = count * MemoryLayout<Float>.size
        let data = Data(bytes: pointer, count: byteCount)
        let sr = UInt32(sampleRate)
        let ch = UInt16(channelCount)
        queue.async { [weak self] in
            self?.appendRawTapBytes(data: data, sampleRate: sr, channelCount: ch, sampleCount: count)
        }
    }

    private func appendRawTapBytes(
        data: Data,
        sampleRate: UInt32,
        channelCount: UInt16,
        sampleCount: Int
    ) {
        if rawTapDone || didFinish { return }

        if rawTapHandle == nil {
            rawTapSampleRate = sampleRate
            rawTapChannels = channelCount
            rawTapMaxSamples = Int(rawTapDurationSeconds * Double(sampleRate) * Double(channelCount))
            FileManager.default.createFile(atPath: rawTapURL.path, contents: nil)
            guard let fh = try? FileHandle(forWritingTo: rawTapURL) else {
                rawTapLogger.error("SessionRecorder could not open raw_tap.wav")
                return
            }
            rawTapHandle = fh
            writeRawTapHeaderStub(to: fh, sampleRate: sampleRate, channelCount: channelCount)
            rawTapHeaderWritten = true
            log("raw tap capture started sr=\(sampleRate) Hz ch=\(channelCount) max=\(Int(rawTapDurationSeconds))s")
        }

        guard let fh = rawTapHandle else { return }

        let remaining = rawTapMaxSamples - rawTapSamplesWritten
        guard remaining > 0 else { return }
        let samplesToWrite = min(sampleCount, remaining)
        let bytesToWrite = samplesToWrite * MemoryLayout<Float>.size
        fh.write(bytesToWrite == data.count ? data : data.prefix(bytesToWrite))
        rawTapSamplesWritten += samplesToWrite

        if rawTapSamplesWritten >= rawTapMaxSamples {
            finalizeRawTapHeader()
            try? fh.close()
            rawTapHandle = nil
            rawTapDone = true
            log("raw tap capture complete \(rawTapSamplesWritten) samples (\(Int(rawTapDurationSeconds))s cap)")
        }
    }

    private func writeRawTapHeaderStub(
        to fh: FileHandle,
        sampleRate: UInt32,
        channelCount: UInt16
    ) {
        let bytesPerSample: UInt16 = 4
        let blockAlign: UInt16 = channelCount * bytesPerSample
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: UInt32(0).littleEndianBytes)
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: UInt32(16).littleEndianBytes)
        header.append(contentsOf: UInt16(3).littleEndianBytes)
        header.append(contentsOf: channelCount.littleEndianBytes)
        header.append(contentsOf: sampleRate.littleEndianBytes)
        header.append(contentsOf: byteRate.littleEndianBytes)
        header.append(contentsOf: blockAlign.littleEndianBytes)
        header.append(contentsOf: UInt16(32).littleEndianBytes)
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: UInt32(0).littleEndianBytes)
        fh.write(header)
    }

    func finalizeRawTapHeader() {
        guard let fh = rawTapHandle else {
            guard rawTapHeaderWritten,
                  let fh = try? FileHandle(forUpdating: rawTapURL) else { return }
            patchRawTapHeader(fh: fh)
            try? fh.close()
            return
        }
        patchRawTapHeader(fh: fh)
    }

    private func patchRawTapHeader(fh: FileHandle) {
        let dataBytes = UInt32(rawTapSamplesWritten * MemoryLayout<Float>.size)
        let riffChunkSize = UInt32(36) + dataBytes
        try? fh.seek(toOffset: 4)
        fh.write(Data(riffChunkSize.littleEndianBytes))
        try? fh.seek(toOffset: 40)
        fh.write(Data(dataBytes.littleEndianBytes))
        _ = try? fh.seekToEnd()
    }

    // MARK: - WAV writer

    /// Write a mono Float32 waveform as a 16-bit PCM WAV file.
    static func writeWav(samples: [Float], sampleRate: Int, to url: URL) {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2
        let chunkSize = 36 + dataSize
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: UInt32(chunkSize).littleEndianBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: UInt32(byteRate).littleEndianBytes)
        data.append(contentsOf: UInt16(2).littleEndianBytes)
        data.append(contentsOf: UInt16(16).littleEndianBytes)
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: UInt32(dataSize).littleEndianBytes)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let pcm = Int16((clamped * 32767.0).rounded())
            data.append(contentsOf: UInt16(bitPattern: pcm).littleEndianBytes)
        }
        try? data.write(to: url)
    }
}

// MARK: - Little-endian helpers

extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF),
         UInt8((self >> 8) & 0xFF),
         UInt8((self >> 16) & 0xFF),
         UInt8((self >> 24) & 0xFF)]
    }
}
