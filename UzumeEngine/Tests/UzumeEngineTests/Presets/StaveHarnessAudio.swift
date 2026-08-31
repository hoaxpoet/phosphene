// StaveHarnessAudio — real PCM into Stave's harness, plus PNG output.
//
// Stave reads ONLY the engine's waveform buffer, so a harness that cannot fill that buffer
// with real audio cannot test the preset at all. Synthetic envelopes are no substitute
// (FA #27): the whole subject is the shape of an actual signal, and a sine would show a
// behaviour no music produces.
//
// Replaces the CHR.3 replay loader, which fed `features.csv` columns — none of which this
// preset reads any more.

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct StaveHarnessAudio {
    let samples: [Float]
    let sampleRate: Float

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              case _ = try file.read(into: buffer),
              let data = buffer.floatChannelData else {
            throw StaveHarnessError.decodeFailed
        }
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channels {
            let p = data[c]
            for i in 0..<frames { mono[i] += p[i] / Float(channels) }
        }
        self.samples = mono
        self.sampleRate = Float(format.sampleRate)
    }

    /// Fill an interleaved-stereo waveform buffer with the window centred on `time`, matching
    /// the engine's live layout (2 × frames floats, L and R adjacent).
    func fill(_ pointer: UnsafeMutablePointer<Float>, frames: Int, at time: Float) {
        let start = Int(time * sampleRate) - frames / 2
        for i in 0..<frames {
            let j = start + i
            let v = (j >= 0 && j < samples.count) ? samples[j] : 0
            pointer[2 * i] = v
            pointer[2 * i + 1] = v
        }
    }

    static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: info.rawValue) else { return nil }
            return context.makeImage()
        }
        guard let cgImage = image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        _ = CGImageDestinationFinalize(dest)
    }
}

enum StaveHarnessError: Error { case decodeFailed }
