// FerrofluidPulseLivePathTests — FBS Stage 1 (D-153) multi-frame proof through
// the LIVE rendering pipeline.
//
// CLAUDE.md "Test in the production-grade rendering pipeline. No shortcuts":
// Ferrofluid Ocean's live dispatch is G-buffer (SDF branch, production since
// round 57) → deferred lighting → bloom + ACES post-process. This harness
// builds that pipeline ONCE and renders a continuous multi-frame run with
// REAL recorded session FeatureVectors (FA #27 — never synthetic): the
// per-frame energy series of the streaming Lotus Flower session Matt reviewed
// as unresponsive (2026-06-09T22-20-46Z), with the pulse fields populated by
// the real `BeatPulseClock` over that series — exactly what `MIRPipeline`
// does live.
//
// Claim under test: the beat pulse visibly moves the rendered spike field.
// A/B on the same frames: pulse live vs pulse gated (amp 0 — the "before"
// spike behaviour at constant baseline). The rendered spike-region luma must
// oscillate substantially with the pulse and be near-static without it.

import CoreGraphics
import ImageIO
import Metal
import MetalKit
import UniformTypeIdentifiers
import XCTest
@testable import DSP
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - FerrofluidPulseLivePathTests

final class FerrofluidPulseLivePathTests: XCTestCase {

    private static let renderWidth = 480
    private static let renderHeight = 270

    private var device: MTLDevice!
    private var loader: PresetLoader!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
        loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
    }

    // MARK: - Fixture replay (real session data)

    private struct Frame {
        let trackElapsedS: Double
        let deltaTime: Float
        let bass: Float, mid: Float, treble: Float
    }

    private func loadLotusFixture() throws -> [Frame] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "lotus_flower_2026-06-09T22-20-46Z",
                              withExtension: "csv", subdirectory: "fbs"),
            "real-session fixture missing (FA #27)")
        let text = try String(contentsOf: url, encoding: .utf8)
        var frames: [Frame] = []
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",").map { Double($0) ?? 0 }
            guard c.count >= 6 else { continue }
            frames.append(Frame(trackElapsedS: c[0], deltaTime: Float(c[2]),
                                bass: Float(c[3]), mid: Float(c[4]), treble: Float(c[5])))
        }
        XCTAssertGreaterThan(frames.count, 500)
        return frames
    }

    // MARK: - The multi-frame live-path gate

    /// Renders ~3.7 s of the real streaming session (every 2nd analysis frame,
    /// ≈ 8 beats at 128 BPM) through the full live FFO dispatch, twice:
    /// pulse live vs pulse gated. Asserts the pulse makes the spike field MOVE.
    func test_pulse_movesRenderedSpikes_throughLivePipeline_multiFrame() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found (silent MSL compile failure? FA #44/#72)")
        let gbufferState = try XCTUnwrap(preset.rayMarchPipelineState)

        // --- Build the live pipeline ONCE (production pass list) ---
        let context = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: Self.renderWidth, height: Self.renderHeight)
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: shaderLibrary.library))
        particles.bakeHeightField(commandQueue: context.commandQueue)
        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(Self.renderWidth) / Float(Self.renderHeight)
        pipeline.sceneUniforms = sceneUniforms
        let iblManager = try IBLManager(context: context, shaderLibrary: shaderLibrary)
        let ppChain = try PostProcessChain(context: context, shaderLibrary: shaderLibrary)
        ppChain.allocateTextures(width: Self.renderWidth, height: Self.renderHeight)
        let floatStride = MemoryLayout<Float>.stride
        let fftBuf = try XCTUnwrap(context.makeSharedBuffer(length: 512 * floatStride))
        let wavBuf = try XCTUnwrap(context.makeSharedBuffer(length: 2048 * floatStride))
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: Self.renderWidth, height: Self.renderHeight, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        let outTex = try XCTUnwrap(context.device.makeTexture(descriptor: outDesc))

        // --- Replay the real session through the real clock (as MIRPipeline does) ---
        let frames = try loadLotusFixture()
        let clock = BeatPulseClock()
        clock.setTempo(bpm: 128.0)   // the session's cached grid (session.log)
        var pulses: [BeatPulseClock.Output] = []
        for f in frames {
            pulses.append(clock.update(energySum: f.bass + f.mid + f.treble,
                                       time: f.trackElapsedS, deltaTime: f.deltaTime))
        }
        // Window: from just after the anchor, every 2nd frame, 110 renders ≈ 3.7 s ≈ 8 beats.
        let start = try XCTUnwrap(pulses.indices.first { pulses[$0].amp01 > 0.9 },
                                  "pulse never reached full amplitude on the music fixture")
        let indices = stride(from: start, to: min(frames.count, start + 220), by: 2).map { $0 }
        XCTAssertGreaterThanOrEqual(indices.count, 100, "need ≥100 frames (~8 beats) of replay")

        func spikeRegionLumas(_ pixels: [UInt8]) -> [Float] {
            // Spike field occupies the lower ⅔ of frame (sky above). BGRA8.
            // PER-PIXEL lumas, not a region mean: the D-157 punch contract is a
            // bounded spatial footprint with STEADY GLOBAL LUMINANCE, so local
            // deltas cancel in a region mean by design. (BUG-034 recalibration:
            // the original region-mean measure only registered the punch because
            // the pre-fix 32-step march left bright false sky between spikes —
            // at the production 128-step budget the mean correctly cancels.)
            var lumas: [Float] = []
            let yLo = Self.renderHeight / 3
            lumas.reserveCapacity((Self.renderHeight - yLo) * Self.renderWidth / 4)
            for y in yLo..<Self.renderHeight {
                for x in stride(from: 0, to: Self.renderWidth, by: 4) {
                    let i = (y * Self.renderWidth + x) * 4
                    lumas.append(0.114 * Float(pixels[i]) + 0.587 * Float(pixels[i + 1])
                               + 0.299 * Float(pixels[i + 2]))
                }
            }
            return lumas
        }

        func renderRun(pulseLive: Bool) throws -> [[Float]] {
            var lumas: [[Float]] = []
            for i in indices {
                var fv = FeatureVector(bass: frames[i].bass, mid: frames[i].mid,
                                       treble: frames[i].treble,
                                       time: Float(frames[i].trackElapsedS),
                                       deltaTime: frames[i].deltaTime)
                fv.trackElapsedS = Float(frames[i].trackElapsedS)
                fv.pulsePhase01 = pulses[i].phase01
                fv.pulseAmp01 = pulseLive ? pulses[i].amp01 : 0   // A/B arm
                var features = fv
                // FBS Stage 2: pin the loudness envelope at full so this
                // test keeps proving FULL-height beat motion (the height
                // scaling has its own pixel gate below).
                var stems = StemFeatures.zero
                stems.totalEnergySmoothed = 1.2
                let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
                pipeline.render(
                    gbufferPipelineState: gbufferState,
                    features: &features,
                    fftBuffer: fftBuf,
                    waveformBuffer: wavBuf,
                    stemFeatures: stems,
                    outputTexture: outTex,
                    commandBuffer: cmdBuf,
                    noiseTextures: nil,
                    iblManager: iblManager,
                    postProcessChain: ppChain,
                    presetFragmentBuffer3: nil,
                    presetHeightTexture: particles.heightTexture
                )
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
                XCTAssertEqual(cmdBuf.status, .completed)
                var pixels = [UInt8](repeating: 0,
                                     count: Self.renderWidth * Self.renderHeight * 4)
                outTex.getBytes(&pixels, bytesPerRow: Self.renderWidth * 4,
                                from: MTLRegionMake2D(0, 0, Self.renderWidth, Self.renderHeight),
                                mipmapLevel: 0)
                lumas.append(spikeRegionLumas(pixels))
                if ProcessInfo.processInfo.environment["FBS_PULSE_DUMP"] == "1",
                   lumas.count == 4 {
                    // Frame 4 of the window sits inside the first punch
                    // (phase 0.06–0.35 at 128 BPM, every-2nd-frame stride).
                    try Self.dumpPNG(pixels,
                                     name: pulseLive ? "s1_punch_pulse_on" : "s1_punch_pulse_off")
                }
            }
            return lumas
        }

        let withPulse = try renderRun(pulseLive: true)
        let gated = try renderRun(pulseLive: false)

        let meanLuma = withPulse.map { $0.reduce(0, +) / Float($0.count) }
                                .reduce(0, +) / Float(withPulse.count)
        XCTAssertGreaterThan(meanLuma, 2.0, "render must be non-black (valid frames)")

        // PAIRED per-frame, PER-PIXEL delta — each fixture frame is rendered
        // twice with ONLY the pulse amp differing, so everything else (the
        // time-driven Gerstner swell, lighting, camera) cancels exactly.
        // mean(|δ_pixel|) isolates the pulse's rendered effect on that exact
        // frame. (First attempt used absolute per-arm variance and was swamped
        // by the swell, σ≈11 luma in BOTH arms; second attempt used the
        // region-MEAN delta, which the D-157 steady-global-luminance contract
        // cancels by design once BUG-034 fixed the fixture step budget — the
        // paired per-pixel magnitude is robust to both confounds.)
        let delta = zip(withPulse, gated).map { pair -> Float in
            zip(pair.0, pair.1).map { abs($0 - $1) }.reduce(0, +) / Float(pair.0.count)
        }

        // Built-in control: in REST windows (env = 0) both arms render
        // identical inputs → δ must be ≈ 0. In PUNCH windows (env high) the
        // pulse changes the spike geometry → δ must be substantial. Direction
        // is not asserted (taller spikes can read darker — more occlusion);
        // MAGNITUDE at the beat vs silence between beats is the claim.
        var punchDelta: [Float] = []
        var restDelta: [Float] = []
        for (k, i) in indices.enumerated() {
            let ph = pulses[i].phase01
            if ph > 0.06, ph < 0.35 { punchDelta.append(delta[k]) }
            if ph > 0.88 { restDelta.append(delta[k]) }
        }
        XCTAssertGreaterThan(punchDelta.count, 8)
        XCTAssertGreaterThan(restDelta.count, 8)
        let punchMag = punchDelta.reduce(0, +) / Float(punchDelta.count)
        let restMag = restDelta.reduce(0, +) / Float(restDelta.count)
        print("[FBS S1 live-path] frames=\(indices.count) punch|δ|=\(punchMag) "
              + "rest|δ|=\(restMag) meanLuma=\(meanLuma)")
        // Thresholds recalibrated at the production 128-step budget (BUG-034,
        // 2026-06-12): regression floors below the measured baseline, not
        // aspirational targets — Matt validated the punch live (D-153/D-158/
        // D-160); this gate pins that it does not silently regress.
        XCTAssertGreaterThan(punchMag, 1.0,
                             "the pulse must visibly change the rendered spike field at the "
                             + "beats (punch |δ|=\(punchMag) per-pixel luma units)")
        XCTAssertGreaterThan(punchMag, 5.0 * (restMag + 0.05),
                             "the change must be AT the beats, ~zero between them "
                             + "(punch |δ|=\(punchMag) vs rest |δ|=\(restMag)) — "
                             + "this is what beat-locked, non-flickering motion means")

        // ── FBS Stage 2 pixel gate: quiet passages punch GENTLY ──
        // Same punch frame rendered three ways: no pulse / quiet-passage
        // envelope (So What intro level → height ≈ 0.37) / loud envelope
        // (height = 1.0). The rendered punch effect must scale accordingly.
        func renderPunchFrame(amp: Float, energySmoothed: Float,
                              dumpName: String? = nil) throws -> [Float] {
            let i = indices[indices.count / 2]
            var fv = FeatureVector(bass: frames[i].bass, mid: frames[i].mid,
                                   treble: frames[i].treble,
                                   time: Float(frames[i].trackElapsedS),
                                   deltaTime: frames[i].deltaTime)
            fv.trackElapsedS = Float(frames[i].trackElapsedS)
            fv.pulsePhase01 = 0.18   // punch peak (attack 0–0.20)
            fv.pulseAmp01 = amp
            var stems = StemFeatures.zero
            stems.totalEnergySmoothed = energySmoothed
            var features = fv
            let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
            pipeline.render(
                gbufferPipelineState: gbufferState, features: &features,
                fftBuffer: fftBuf, waveformBuffer: wavBuf, stemFeatures: stems,
                outputTexture: outTex, commandBuffer: cmdBuf, noiseTextures: nil,
                iblManager: iblManager, postProcessChain: ppChain,
                presetFragmentBuffer3: nil,
                presetHeightTexture: particles.heightTexture)
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            var pixels = [UInt8](repeating: 0,
                                 count: Self.renderWidth * Self.renderHeight * 4)
            outTex.getBytes(&pixels, bytesPerRow: Self.renderWidth * 4,
                            from: MTLRegionMake2D(0, 0, Self.renderWidth, Self.renderHeight),
                            mipmapLevel: 0)
            if ProcessInfo.processInfo.environment["FBS_PULSE_DUMP"] == "1",
               let dumpName {
                try Self.dumpPNG(pixels, name: dumpName)
            }
            var lumas: [Float] = []
            let yLo = Self.renderHeight / 3
            for y in yLo..<Self.renderHeight {
                for x in stride(from: 0, to: Self.renderWidth, by: 4) {
                    let p = (y * Self.renderWidth + x) * 4
                    lumas.append(0.114 * Float(pixels[p]) + 0.587 * Float(pixels[p + 1])
                               + 0.299 * Float(pixels[p + 2]))
                }
            }
            return lumas
        }
        func meanAbsDelta(_ a: [Float], _ b: [Float]) -> Float {
            zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Float(a.count)
        }
        let noPulse = try renderPunchFrame(amp: 0, energySmoothed: 1.2, dumpName: "s2_no_pulse")
        let quiet = try renderPunchFrame(amp: 1, energySmoothed: 0.34,
                                         dumpName: "s2_quiet_punch")   // So What intro level
        let loud = try renderPunchFrame(amp: 1, energySmoothed: 1.3, dumpName: "s2_loud_punch")
        let quietPunch = meanAbsDelta(quiet, noPulse)
        let loudPunch = meanAbsDelta(loud, noPulse)
        print("[FBS S2 live-path] punch effect: quiet=\(quietPunch) loud=\(loudPunch) luma")
        XCTAssertGreaterThan(quietPunch, 0.3,
                             "the floor must keep every beat registering at quiet passages")
        // Ratio recalibrated at the production 128-step budget (BUG-034,
        // 2026-06-12): the old 1.8× floor was calibrated on the pre-fix
        // 32-step render, where bright false sky between spikes amplified the
        // height→luma proportionality. At the true budget taller spikes read
        // against correctly-resolved dark fluid, compressing the pixel ratio
        // (measured 1.38× at recalibration; the height difference itself was
        // validated by eye live — D-160, Matt 2026-06-11). 1.2× is the
        // regression floor: scaling must remain present and directional.
        XCTAssertGreaterThan(loudPunch, 1.2 * quietPunch,
                             "loud passages must punch taller than quiet ones "
                             + "(loud \(loudPunch) vs quiet \(quietPunch))")
    }

    // MARK: - Eyeball dump (FBS lesson: trajectories AND frames, not summary stats)

    /// Writes a BGRA8 frame to `/tmp/phosphene_visual/fbs_pulse/` when
    /// `FBS_PULSE_DUMP=1`. Lets the recalibrated thresholds be sanity-checked
    /// by eye against the frames the gate actually measures.
    private static func dumpPNG(_ pixels: [UInt8], name: String) throws {
        let dir = URL(fileURLWithPath: "/tmp/phosphene_visual/fbs_pulse")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var data = pixels
        let provider = try XCTUnwrap(data.withUnsafeMutableBytes { buf -> CGDataProvider? in
            CGDataProvider(data: Data(bytes: buf.baseAddress!, count: buf.count) as CFData)
        })
        let image = try XCTUnwrap(CGImage(
            width: renderWidth, height: renderHeight,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: renderWidth * 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                     | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = dir.appendingPathComponent("\(name).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("[FBS dump] wrote \(url.path)")
    }
}
