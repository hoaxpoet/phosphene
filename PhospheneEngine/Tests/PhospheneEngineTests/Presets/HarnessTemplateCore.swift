// HarnessTemplateCore — the shared multi-frame harness spine (QG.4).
//
// Every rendering paradigm gets a reference multi-frame harness that drives the
// SAME dispatch path the live app uses, so PRESET_SESSION_CHECKLIST's "write or
// extend the multi-frame harness FIRST" is a copy-adapt from a named template,
// not a from-scratch build. This file is the re-usable spine those templates and
// the reference `AuroraVeilMVWarpAccumulationTest` share:
//
//   - env-gating (`HARNESS_TEMPLATES=1`)
//   - zeroed silence audio buffers (fft / waveform / stem / spectral history)
//   - capture-texture allocation + one-shot clear + BGRA / rgba16Float readback
//   - the per-frame silence FeatureVector
//   - metric hooks: non-degeneracy (non-constant + non-NaN), luma, and the 64-bit
//     dHash / Hamming pair the golden-regression assertions use
//
// The paradigm-specific pass sequence (which pipelines, which slots) stays in each
// template — this file is only the plumbing every paradigm has in common. The
// dHash is byte-for-byte the `ArachneSpiderRenderTests` algorithm (9×8 luma grid,
// BGRA weighting) so golden captures are comparable across the suite.
//
// GPU test — env-gated, NOT in the default parallel run (some subjects exceed the
// timing budget). Wired into `closeout_evidence.sh` for preset increments.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Shared

// MARK: - HarnessTemplateCore

enum HarnessTemplateCore {

    /// The single env gate for all QG.4 templates. AuroraVeil keeps its own
    /// `AURORA_VEIL_MVWARP_DIAG` gate (it predates this and is a pure diagnostic);
    /// the three QG.4 templates gate on this.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HARNESS_TEMPLATES"] == "1"
    }

    // MARK: Silence buffers

    /// The four zeroed audio buffers every headless preset render binds at
    /// slots 1 (fft), 2 (waveform), 3 (stem), 5 (spectral history). Silence =
    /// all-zero, the AuroraVeil / acceptance baseline.
    struct SilenceBuffers {
        let fft: MTLBuffer
        let waveform: MTLBuffer
        let stem: MTLBuffer
        let history: MTLBuffer
    }

    static func makeSilenceBuffers(_ context: MetalContext) throws -> SilenceBuffers {
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = context.makeSharedBuffer(length: 512 * floatStride),
            let wav = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw HarnessError.bufferAllocationFailed }
        // Shared buffers are not guaranteed zeroed — zero them explicitly.
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        return SilenceBuffers(fft: fft, waveform: wav, stem: stem, history: hist)
    }

    // MARK: Textures

    /// A `.shared`, render-target + shader-read texture we can read pixels back from.
    /// `pixelFormat: nil` ⇒ the context's drawable format; pass `.rgba16Float` for
    /// staged intermediate stages (which are compiled for the HDR format).
    static func makeCaptureTexture(
        _ context: MetalContext,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat? = nil
    ) throws -> MTLTexture {
        guard let tex = context.makeSharedTexture(
            width: width, height: height, pixelFormat: pixelFormat,
            usage: [.renderTarget, .shaderRead]
        ) else { throw HarnessError.textureAllocationFailed }
        return tex
    }

    /// One-shot clear-to-black pass for the supplied textures (accumulator init).
    static func clear(_ textures: [MTLTexture], _ context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        for tex in textures {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = tex
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            desc.colorAttachments[0].storeAction = .store
            if let enc = cmd.makeRenderCommandEncoder(descriptor: desc) { enc.endEncoding() }
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    /// Read a drawable-format (bgra8) texture back into a BGRA byte array.
    static func readBGRA(_ tex: MTLTexture, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&pixels, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    /// Read an `.rgba16Float` texture back into raw half-float bytes (8 bytes/pixel).
    static func readHalf(_ tex: MTLTexture, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 8)
        tex.getBytes(&bytes, bytesPerRow: width * 8,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    // MARK: Per-frame drive

    /// Silence FeatureVector for frame `i`. Time advances from `startTime` at
    /// 60 fps — matches the AuroraVeil accumulation loop (start t=3.0).
    static func silenceFeature(frame i: Int, startTime: Float = 3.0) -> FeatureVector {
        let dt: Float = 1.0 / 60.0
        return FeatureVector(time: Float(i) * dt + startTime, deltaTime: dt)
    }

    // MARK: Metrics — drawable-format frames

    /// Frame is non-degenerate: not a constant colour (has spatial structure).
    /// bgra8 can't hold NaN, so "non-NaN" is vacuous for this path.
    static func isNonConstant(_ pixels: [UInt8]) -> Bool {
        guard pixels.count >= 8 else { return false }
        let first = pixels[0], second = pixels[1], third = pixels[2]
        var i = 4
        while i + 2 < pixels.count {
            if pixels[i] != first || pixels[i + 1] != second || pixels[i + 2] != third {
                return true
            }
            i += 4
        }
        return false
    }

    static func maxLuma(_ pixels: [UInt8]) -> Double {
        var m = 0.0
        var i = 0
        while i + 2 < pixels.count {
            let luma = 0.114 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.299 * Double(pixels[i + 2])
            if luma > m { m = luma }
            i += 4
        }
        return m / 255.0
    }

    static func meanLuma(_ pixels: [UInt8]) -> Double {
        var sum = 0.0
        var n = 0
        var i = 0
        while i + 2 < pixels.count {
            sum += 0.114 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.299 * Double(pixels[i + 2])
            n += 1
            i += 4
        }
        return n > 0 ? (sum / Double(n)) / 255.0 : 0
    }

    // MARK: Metrics — rgba16Float (staged intermediate) frames

    struct HalfStats {
        let nonConstant: Bool
        let hasNaN: Bool
        let maxMagnitude: Float
    }

    /// Non-degeneracy of a raw rgba16Float readback: non-constant + non-NaN +
    /// its peak channel magnitude (so a caller can assert the stage wrote signal).
    static func halfStats(_ bytes: [UInt8]) -> HalfStats {
        var firstBits: UInt16?
        var nonConstant = false
        var hasNaN = false
        var maxMag: Float = 0
        var i = 0
        while i + 1 < bytes.count {
            let bits = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
            if (bits & 0x7C00) == 0x7C00 && (bits & 0x03FF) != 0 { hasNaN = true }
            if let f = firstBits { if bits != f { nonConstant = true } } else { firstBits = bits }
            let mag = abs(halfToFloat(bits))
            if mag.isFinite && mag > maxMag { maxMag = mag }
            i += 2
        }
        return HalfStats(nonConstant: nonConstant, hasNaN: hasNaN, maxMagnitude: maxMag)
    }

    /// IEEE 754 half → float. Handles subnormals, inf, NaN.
    static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = UInt32(h & 0x7C00) >> 10
        let mant = UInt32(h & 0x03FF)
        let bits: UInt32
        if exp == 0 {
            if mant == 0 {
                bits = sign
            } else {
                // subnormal → normalize
                var e: UInt32 = 127 - 15 + 1
                var m = mant
                while (m & 0x0400) == 0 { m <<= 1; e -= 1 }
                m &= 0x03FF
                bits = sign | (e << 23) | (m << 13)
            }
        } else if exp == 0x1F {
            bits = sign | 0x7F800000 | (mant << 13)   // inf / NaN
        } else {
            bits = sign | ((exp + 112) << 23) | (mant << 13)
        }
        return Float(bitPattern: bits)
    }

    // MARK: dHash (golden regression) — canonical 9×8 grid, BGRA luma

    /// 64-bit dHash: downsample to a 9×8 luma grid, compare adjacent horizontal
    /// cells. Byte-identical to `ArachneSpiderRenderTests.dHash` so golden captures
    /// stay comparable across the suite. BGRA byte order.
    static func dHash(_ pixels: [UInt8], width: Int, height: Int) -> UInt64 {
        let cols = 9, rows = 8
        var grid = [Float](repeating: 0, count: cols * rows)
        let cellW = max(width / cols, 1)
        let cellH = max(height / rows, 1)
        for row in 0..<rows {
            for col in 0..<cols {
                var sum: Float = 0
                var count = 0
                for y in (row * cellH)..<min((row + 1) * cellH, height) {
                    for x in (col * cellW)..<min((col + 1) * cellW, width) {
                        let idx = (y * width + x) * 4
                        sum += 0.114 * Float(pixels[idx]) + 0.587 * Float(pixels[idx + 1]) + 0.299 * Float(pixels[idx + 2])
                        count += 1
                    }
                }
                grid[row * cols + col] = count > 0 ? sum / Float(count) : 0
            }
        }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 where grid[row * cols + col + 1] > grid[row * cols + col] {
                hash |= UInt64(1) << UInt64(row * 8 + col)
            }
        }
        return hash
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}

// MARK: - HarnessError

enum HarnessError: Error {
    case bufferAllocationFailed
    case textureAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
    case presetNotFound(String)
    case setupFailed(String)
}
