// WitchlightFlashBudgetTests — the WITCHLIGHT_DESIGN §5 numbers, measured.
//
// §5 sets a flash budget UP FRONT rather than tuning one down after the fact, and says every
// number in it "is a WL.2 requirement, measured and reported in its closeout". The
// flashes/second half of that lives in `MultiPassFlashHarnessTests` alongside every other
// certified preset. This file measures the rest — the peak luminance, the per-frame swing,
// and the head flare's spatial extent — because those are Witchlight-specific ceilings that
// no shared gate knows about.
//
// The thing being guarded against is anti-reference `12`: in the inspiration source the head
// flare saturates most of the frame to white on a mid-band hit, erasing the subject, on
// roughly a fifth of sampled frames. It re-fires on every hit with no refractory. That is a
// fidelity failure before it is a safety one, and it is the reason §5 exists.
//
// The ceilings are enforced in `WitchlightPath` / `Witchlight.metal` — a CPU-side refractory
// and amplitude ceiling, and a fixed flare extent in the vertex shader that does not grow
// with intensity. This file only measures; a number outside budget is a shader fix.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - WitchlightFlashBudgetTests

@Suite("Witchlight flash budget (WITCHLIGHT_DESIGN §5)")
@MainActor
struct WitchlightFlashBudgetTests {

    nonisolated static let width = 480
    nonisolated static let height = 270

    // MARK: - §5 ceilings

    private static let peakMeanLuminanceCeiling = 0.35
    private static let maxDeltaPerFrameCeiling = 0.06
    private static let extentAtHalfPeakCeiling = 0.03      // 3 % of frame area
    private static let extentAtTenthPeakCeiling = 0.12     // 12 % of frame area

    @Test("the composite never exceeds the §5 peak luminance or per-frame swing")
    func luminanceCeilingsHold() throws {
        let rig = try Rig()
        // The worst case for BOTH ceilings at once: a bass-dev impulse train firing the flare
        // as often as its refractory permits, over the fastest harmonic motion in the measured
        // corpus (love_rehab, 15.4 circles per 30 s), with the trail grown in.
        var series: [Double] = []
        for i in 0..<1800 {
            guard let pixels = rig.renderComposite(Self.worstCaseFrame(index: i)) else { continue }
            series.append(Self.meanRelativeLuminance(pixels))
        }
        let peak = series.max() ?? 0
        let maxDelta = zip(series, series.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        print(String(format: "[witchlight-§5] peak mean luminance %.4f (ceiling %.2f) · "
                           + "max Δ/frame %.4f (ceiling %.2f) · flares fired %d",
                     peak, Self.peakMeanLuminanceCeiling,
                     maxDelta, Self.maxDeltaPerFrameCeiling, rig.stroke.path.flareCount))

        #expect(peak <= Self.peakMeanLuminanceCeiling, """
            peak full-frame mean relative luminance \(peak) exceeds the §5 ceiling of \
            \(Self.peakMeanLuminanceCeiling). The source reaches ~1.0 (anti-reference `12`); \
            this is a shader fix, not a waiver.
            """)
        #expect(maxDelta <= Self.maxDeltaPerFrameCeiling, """
            max per-frame luminance swing \(maxDelta) exceeds the §5 ceiling of \
            \(Self.maxDeltaPerFrameCeiling). §5 targets 0.00 flashes/s BY CONSTRUCTION — no \
            transition may reach the 0.10 WCAG swing threshold in the first place.
            """)
    }

    @Test("the head flare stays inside its §5 spatial extent caps")
    func flareExtentCapsHold() throws {
        let rig = try Rig()
        // Find the brightest frame — by construction that is a flare peak, since the flare is
        // the only thing on the field that is not a thin line or a pinpoint.
        var brightest: [UInt8] = []
        var brightestPeak = 0.0
        for i in 0..<1200 {
            // Geometry ONLY, on black: the star field's pinpoints would otherwise count toward
            // the flare's "area above half peak" and the measurement would read the sky.
            guard let pixels = rig.renderGeometryOnly(Self.worstCaseFrame(index: i)) else { continue }
            let peak = Self.peakPixelLuminance(pixels)
            if peak > brightestPeak { brightestPeak = peak; brightest = pixels }
        }
        #expect(brightestPeak > 0.05, "no flare was ever measured — the drive never fired one")

        let halfPeak = Self.areaFraction(brightest, above: brightestPeak * 0.5)
        let tenthPeak = Self.areaFraction(brightest, above: brightestPeak * 0.1)
        print(String(format: "[witchlight-§5] flare extent: %.3f %% of frame at ≥50 %% peak "
                           + "(cap %.1f %%) · %.3f %% at ≥10 %% peak (cap %.1f %%) · peak pixel %.3f",
                     halfPeak * 100, Self.extentAtHalfPeakCeiling * 100,
                     tenthPeak * 100, Self.extentAtTenthPeakCeiling * 100, brightestPeak))

        #expect(halfPeak <= Self.extentAtHalfPeakCeiling, """
            \(halfPeak * 100) % of the frame sits above half the flare's peak intensity, over \
            the §5 cap of \(Self.extentAtHalfPeakCeiling * 100) %. `03` is the bound: a real \
            burning head's hot core is roughly the diameter of the trail.
            """)
        #expect(tenthPeak <= Self.extentAtTenthPeakCeiling, """
            \(tenthPeak * 100) % of the frame sits above a tenth of the flare's peak, over the \
            §5 cap of \(Self.extentAtTenthPeakCeiling * 100) %. The source exceeds 50 % (`12`).
            """)
    }

    // MARK: - Worst-case drive

    private struct Frame {
        var features: FeatureVector
        var stems: StemFeatures
    }

    /// Maximal harmonic motion + a 4.5 Hz bass-dev impulse train, i.e. the flare asking to
    /// fire far more often than its refractory will allow.
    private static func worstCaseFrame(index: Int) -> Frame {
        let fps: Float = 60
        let t = Float(index) / fps
        let period = fps / 4.5
        let beatPhase = Float(index).truncatingRemainder(dividingBy: period) / period
        let env = exp(-beatPhase * 6.0)

        var f = FeatureVector()
        f.time = t
        f.deltaTime = 1 / fps
        f.aspectRatio = Float(width) / Float(height)
        f.bass = 0.55 + 0.15 * env; f.mid = 0.52; f.treble = 0.5
        f.bassDev = env * 0.85                     // the flare's driver, at the measured p99
        f.bassRel = 0.1
        f.spectralCentroid = 0.12 + 0.08 * env
        f.valence = 0.2
        f.arousal = 0.85
        f.beatPhase01 = beatPhase
        f.barPhase01 = Float(index).truncatingRemainder(dividingBy: period * 4) / (period * 4)
        f.beatsPerBar = 4
        var phase = (t * 3.2).truncatingRemainder(dividingBy: 2 * .pi)
        if phase > .pi { phase -= 2 * .pi }
        f.tonalPhaseFifths = phase
        f.tonalConsonance = 0.12

        var s = StemFeatures()
        s.drumsEnergy = 0.5; s.bassEnergy = 0.5; s.otherEnergy = 0.4; s.vocalsEnergy = 0.3
        s.drumsEnergyDev = env * 0.85; s.bassEnergyDev = env * 0.85
        return Frame(features: f, stems: s)
    }

    // MARK: - Measurement

    /// WCAG relative luminance, full-frame mean. Same reducer the shared flash gate uses.
    private static func meanRelativeLuminance(_ bgra: [UInt8]) -> Double {
        var sum = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            sum += relativeLuminance(bgra[i + 2], bgra[i + 1], bgra[i])
        }
        return sum / Double(bgra.count / 4)
    }

    private static func peakPixelLuminance(_ bgra: [UInt8]) -> Double {
        var peak = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            peak = max(peak, relativeLuminance(bgra[i + 2], bgra[i + 1], bgra[i]))
        }
        return peak
    }

    private static func areaFraction(_ bgra: [UInt8], above threshold: Double) -> Double {
        var count = 0
        for i in stride(from: 0, to: bgra.count, by: 4)
        where relativeLuminance(bgra[i + 2], bgra[i + 1], bgra[i]) > threshold { count += 1 }
        return Double(count) / Double(bgra.count / 4)
    }

    private static func relativeLuminance(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255.0
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    // MARK: - Rig

    private final class Rig {
        let context: MetalContext
        let stroke: WitchlightStroke
        private let preset: PresetLoader.LoadedPreset
        private let texture: MTLTexture
        private let fft: MTLBuffer
        private let waveform: MTLBuffer

        init() throws {
            context = try MetalContext()
            let library = try ShaderLibrary(context: context)
            let loader = PresetLoader(device: context.device, pixelFormat: context.pixelFormat,
                                      loadBuiltIn: true)
            guard let loaded = loader.presets.first(where: { $0.descriptor.name == "Witchlight" }) else {
                throw WitchlightHarnessError.setupFailed("Witchlight did not load")
            }
            preset = loaded
            stroke = try WitchlightStroke(device: context.device, library: library.library,
                                          pixelFormat: context.pixelFormat)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let target = context.device.makeTexture(descriptor: descriptor) else {
                throw WitchlightHarnessError.setupFailed("target texture")
            }
            texture = target
            let stride = MemoryLayout<Float>.stride
            guard let fftBuffer = context.makeSharedBuffer(length: 512 * stride),
                  let waveformBuffer = context.makeSharedBuffer(length: 2048 * stride) else {
                throw WitchlightHarnessError.setupFailed("audio buffers")
            }
            fft = fftBuffer
            waveform = waveformBuffer
        }

        func renderComposite(_ frame: Frame) -> [UInt8]? { render(frame, includeSky: true) }

        func renderGeometryOnly(_ frame: Frame) -> [UInt8]? { render(frame, includeSky: false) }

        /// One frame: tick the stroke and draw it, on the single command buffer the live path
        /// uses (`update` encodes into the same buffer the render pass is committed on).
        private func render(_ frame: Frame, includeSky: Bool) -> [UInt8]? {
            guard let cmd = context.commandQueue.makeCommandBuffer() else { return nil }
            stroke.update(features: frame.features, stemFeatures: frame.stems, commandBuffer: cmd)
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = texture
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let encoder = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
            var features = frame.features
            var stems = frame.stems
            if includeSky {
                encoder.setRenderPipelineState(preset.pipelineState)
                encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
                encoder.setFragmentBuffer(fft, offset: 0, index: 1)
                encoder.setFragmentBuffer(waveform, offset: 0, index: 2)
                encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            stroke.render(encoder: encoder, features: frame.features)
            encoder.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return pixels
        }
    }
}
