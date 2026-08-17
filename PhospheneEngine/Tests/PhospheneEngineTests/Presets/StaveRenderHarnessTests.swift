// StaveRenderHarnessTests — Stave's production-path multi-frame harness (CHR.3b).
//
// The checklist obligation: "every preset increment that depends on temporal behaviour must
// include a test running the same dispatch path the live app uses." Stave's whole subject is
// the waveform read fresh every frame, so a single-frame test proves almost nothing.
//
// Dispatch path exercised — `RenderPipeline.drawParticleMode`, verbatim in structure: ONE
// render encoder per frame, cleared, with the preset's `pipelineState` drawing the ground
// triangle and then `ParticleGeometry.render` drawing the dispersion into the SAME encoder.
//
// ⚠ The harness must FILL THE WAVEFORM BUFFER, because that buffer is the preset's only
// driver — it reads nothing else from the audio pipeline. A harness that leaves it zeroed
// renders a flat line and would report a dead preset as working (the "harness must carry every
// route" failure class). The env-gated test feeds real PCM from a session's `raw_tap.wav`.

import Testing
import Foundation
import Metal
import AVFoundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("StaveRenderHarness")
@MainActor
struct StaveRenderHarnessTests {

    private static let presetName = "Stave"

    // MARK: - Subject

    private final class Subject {
        let preset: PresetLoader.LoadedPreset
        let geometry: StaveTrace
        let buffers: HarnessTemplateCore.SilenceBuffers
        let waveform: MTLBuffer
        /// ⚠ The harness bypasses `RenderPipeline`, which is where production publishes
        /// `waveformOccupancy`. Without ticking it here Stave's fan would read a permanent
        /// zero and the preset would render flat — a harness fault reported as a dead preset.
        var occupancy = WaveformOccupancy()

        init(preset: PresetLoader.LoadedPreset, geometry: StaveTrace,
             buffers: HarnessTemplateCore.SilenceBuffers, waveform: MTLBuffer) {
            self.preset = preset
            self.geometry = geometry
            self.buffers = buffers
            self.waveform = waveform
        }
    }

    private static func makeSubject(_ ctx: MetalContext, sampleCount: Int = 1024,
                                    sampleRate: Float = 48_000,
                                    zoom: Float? = nil,
                                    frameKnee: Float? = nil,
                                    tilt: Float? = nil,
                                    fanMin: Float? = nil,
                                    fanMax: Float? = nil) throws -> Subject {
        // Fall back to the PRODUCTION defaults, never to hardcoded numbers — a harness that
        // supplies its own defaults silently tests something the app does not ship.
        let shipped = StaveConfiguration(sampleRate: sampleRate)
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound(presetName)
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        // Interleaved stereo, matching the engine's `waveformBuffer`.
        guard let waveform = ctx.makeSharedBuffer(length: sampleCount * 2 * MemoryLayout<Float>.stride) else {
            throw HarnessError.setupFailed("waveform buffer")
        }
        _ = waveform.contents().initializeMemory(
            as: UInt8.self, repeating: 0, count: sampleCount * 2 * MemoryLayout<Float>.stride)
        let geometry = try StaveTrace(device: ctx.device, library: lib.library,
                                      waveform: waveform,
                                      configuration: StaveConfiguration(sampleCount: sampleCount,
                                                                      tilt: tilt ?? shipped.tilt,
                                                                      fanMin: fanMin ?? shipped.fanMin,
                                                                      fanMax: fanMax ?? shipped.fanMax,
                                                                      zoom: zoom ?? shipped.zoom,
                                                                      frameKnee: frameKnee ?? shipped.frameKnee,
                                                                      sampleRate: sampleRate),
                                      pixelFormat: ctx.pixelFormat)
        return Subject(preset: preset, geometry: geometry, buffers: buffers, waveform: waveform)
    }

    private static func renderFrame(
        ctx: MetalContext, subject: Subject, texture: MTLTexture,
        features: inout FeatureVector, width: Int, height: Int
    ) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        let frames = subject.waveform.length / (2 * MemoryLayout<Float>.stride)
        let wave = subject.waveform.contents().bindMemory(to: Float.self, capacity: frames * 2)
        subject.occupancy.advance(waveform: wave, frames: frames, deltaTime: features.deltaTime)
        features.waveformOccupancy = subject.occupancy.value
        subject.geometry.update(features: features, stemFeatures: .zero, commandBuffer: cmd)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            throw HarnessError.renderFailed
        }
        encoder.setRenderPipelineState(subject.preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(subject.buffers.fft, offset: 0, index: 1)
        encoder.setFragmentBuffer(subject.waveform, offset: 0, index: 2)
        var stems = StemFeatures.zero
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        encoder.setFragmentBuffer(subject.buffers.history, offset: 0, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        subject.geometry.render(encoder: encoder, features: features)
        encoder.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }
        return HarnessTemplateCore.readBGRA(texture, width: width, height: height)
    }

    // MARK: - Silence regression (default suite)

    @Test("particle-path silence: ground persists, never black, wave flattens (D-037)")
    func staveParticlePath_silenceIsStableAndNonBlack() throws {
        let width = 256, height = 256
        let ctx = try MetalContext()
        let subject = try Self.makeSubject(ctx)
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        var last: [UInt8] = []
        for i in 0..<60 {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            features.aspectRatio = Float(width) / Float(height)
            last = try Self.renderFrame(ctx: ctx, subject: subject, texture: texture,
                                        features: &features, width: width, height: height)
        }

        // D-037: silence renders the ground, not black.
        var darkest: UInt8 = 255
        for i in stride(from: 0, to: last.count, by: 4) {
            let b: UInt8 = last[i], g: UInt8 = last[i + 1], r: UInt8 = last[i + 2]
            let peak: UInt8 = max(b, max(g, r))
            if peak < darkest { darkest = peak }
        }
        #expect(darkest > 2, "silence frame has a fully black pixel — D-037 floor breached")

        // At silence the fan must be at rest: nothing on screen, nothing to disperse.
        #expect(subject.geometry.fan <= subject.geometry.configuration.fanMin + 1e-3,
                "fan did not settle to rest at silence (\(subject.geometry.fan))")
    }

    @Test("a zeroed waveform buffer produces a flat wave — the harness's own guard")
    func silentWaveformIsFlat() throws {
        let ctx = try MetalContext()
        let subject = try Self.makeSubject(ctx)
        var features = HarnessTemplateCore.silenceFeature(frame: 1)
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return }
        subject.geometry.update(features: features, stemFeatures: .zero, commandBuffer: cmd)
        _ = features
        // Every curve sample must be zero. This is the guard on the guard: if a future change
        // makes the model synthesise motion from nothing, the silence test above would still
        // pass while the preset animated at silence, which L5 forbids.
        let peak = subject.geometry.model.curves.map(abs).max() ?? 0
        #expect(peak < 1e-6, "model produced \(peak) from a silent buffer")
    }

    // MARK: - Real-audio sequence (env-gated)

    @Test("render a Stave sequence from real audio (STAVE_RENDER_WAV=…)")
    func renderStaveSequence() throws {
        let env = ProcessInfo.processInfo.environment
        guard let wavPath = env["STAVE_RENDER_WAV"] else {
            print("[stave] STAVE_RENDER_WAV not set — skipping")
            return
        }
        let width = Int(env["STAVE_RENDER_W"] ?? "") ?? 1067
        let height = Int(env["STAVE_RENDER_H"] ?? "") ?? 600
        let startAt = Float(env["STAVE_RENDER_START"] ?? "") ?? 40
        let seconds = Float(env["STAVE_RENDER_SECONDS"] ?? "") ?? 5
        let outDir = URL(fileURLWithPath: env["STAVE_RENDER_OUT"]
                         ?? NSTemporaryDirectory().appending("stave_render"))
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let audio = try StaveHarnessAudio(url: URL(fileURLWithPath: (wavPath as NSString).expandingTildeInPath))
        let ctx = try MetalContext()
        let subject = try Self.makeSubject(
            ctx,
            sampleRate: audio.sampleRate,
            zoom: env["STAVE_RENDER_ZOOM"].flatMap(Float.init),
            frameKnee: env["STAVE_RENDER_KNEE"].flatMap(Float.init),
            // Overrides exist so the reference set's ANTI-references stay reproducible: each
            // one is a real measured failure from CHR.3b–e, not a hypothetical, and the
            // README records the exact settings that regenerate it.
            tilt: env["STAVE_RENDER_TILT"].flatMap(Float.init),
            fanMin: env["STAVE_RENDER_FANMIN"].flatMap(Float.init),
            fanMax: env["STAVE_RENDER_FANMAX"].flatMap(Float.init))
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)
        let sampleCount = subject.geometry.configuration.sampleCount
        let wavePtr = subject.waveform.contents().bindMemory(to: Float.self, capacity: sampleCount * 2)

        let fps: Float = 60
        let frameCount = Int(seconds * fps)
        // Warm the per-band level envelope before capturing — it is a 20 s tracker, so the
        // first frames are it settling rather than the preset's steady behaviour.
        let warmup = Int(6 * fps)
        var written = 0
        var fanMin = Float.greatestFiniteMagnitude, fanMax: Float = 0
        // Frame fit: the largest |y| any band reaches, in NDC half-heights. > 1 means the
        // wave is drawn outside the frame and is being clipped by the viewport.
        var peakY: Float = 0
        var overflowFrames = 0

        for f in -warmup..<frameCount {
            let t = startAt + Float(f) / fps
            audio.fill(wavePtr, frames: sampleCount, at: max(t, 0))
            var features = FeatureVector(time: t, deltaTime: 1 / fps)
            features.aspectRatio = Float(width) / Float(height)
            let pixels = try Self.renderFrame(ctx: ctx, subject: subject, texture: texture,
                                              features: &features, width: width, height: height)
            guard f >= 0 else { continue }
            fanMin = min(fanMin, subject.geometry.fan)
            fanMax = max(fanMax, subject.geometry.fan)
            let model = subject.geometry.model
            let bands = StaveBandPlan.count
            var framePeak: Float = 0
            for band in 0..<bands {
                let ratio = Float(band) / Float(bands - 1)
                let dev = 2 * pow(ratio, model.configuration.spacing) - 1
                let offset = model.fan * dev
                let base = band * model.configuration.sampleCount
                for i in 0..<model.configuration.sampleCount {
                    let y = (model.curves[base + i] + offset) * model.configuration.zoom
                    let knee = model.configuration.frameKnee
                    var mag = abs(y)
                    if knee > 0 && mag > knee {
                        let head = 1 - knee
                        mag = knee + head * tanhf((mag - knee) / head)
                    }
                    framePeak = max(framePeak, mag)
                }
            }
            peakY = max(peakY, framePeak)
            if framePeak > 1 { overflowFrames += 1 }
            try StaveHarnessAudio.writePNG(
                bgra: pixels, width: width, height: height,
                to: outDir.appendingPathComponent(String(format: "stave_seq_%04d.png", written)))
            written += 1
        }
        print("[stave] wrote \(written) frames to \(outDir.path)")
        print("[stave] fan over the sequence: \(String(format: "%.3f..%.3f", fanMin, fanMax))")
        print("[stave] peak |y| \(String(format: "%.3f", peakY)) NDC"
              + "  (frames drawn outside the frame: \(overflowFrames)/\(written))"
              + "  → fits at zoom \(String(format: "%.1f", 100 * (1 - 1 / max(peakY, 1)))) %")
    }
}
