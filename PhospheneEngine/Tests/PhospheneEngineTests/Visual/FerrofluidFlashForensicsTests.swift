// FerrofluidFlashForensicsTests — FBS flash root-cause diagnostic.
//
// Re-renders a REAL session's per-frame inputs through the live FFO dispatch
// (SDF G-buffer → lighting → bloom) and measures the RENDERED PIXELS frame by
// frame — the phenomenon itself, not its input correlates. Detects flash
// events (per-frame luma steps, near-white pixel bursts) and localises them.
//
// Env-gated: set PHOSPHENE_SESSION_DIR to a session directory and
// PHOSPHENE_FLASH_WINDOW to "<segIndex>:<loSec>:<hiSec>" (segments split on
// track_elapsed_s resets). Skips silently otherwise (diagnostic, not a gate).
//
// Faithfully replicates the CPU-side per-frame modulation the live app applies
// (applyAudioModulation): smoothed light intensity (BUG-038), valence tint,
// arousal fog, aurora drums driver (D-127/BUG-041/FBS.S3.2), camera dolly —
// driven from the session's recorded series, deterministic dt from the CSV.

import Metal
import MetalKit
import XCTest
@testable import DSP
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidFlashForensicsTests: XCTestCase {

    private static let renderWidth = 480
    private static let renderHeight = 270

    func test_renderSessionWindow_andMeasureFlashes() throws {
        guard let dir = ProcessInfo.processInfo.environment["PHOSPHENE_SESSION_DIR"],
              let windowSpec = ProcessInfo.processInfo.environment["PHOSPHENE_FLASH_WINDOW"] else {
            throw XCTSkip("diagnostic — set PHOSPHENE_SESSION_DIR + PHOSPHENE_FLASH_WINDOW (seg:lo:hi)")
        }
        let parts = windowSpec.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { throw XCTSkip("PHOSPHENE_FLASH_WINDOW must be seg:lo:hi") }
        let (segIdx, lo, hi) = (Int(parts[0]), parts[1], parts[2])
        // Ablation: none | pulse | aurora | light | spikes-frozen — disable ONE
        // layer to attribute measured flashes mechanically.
        let ablate = ProcessInfo.processInfo.environment["PHOSPHENE_FLASH_ABLATE"] ?? "none"

        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let preset = try XCTUnwrap(loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" })
        let gbufferState = try XCTUnwrap(preset.rayMarchPipelineState)

        // --- Load the session series (features + stems by frame) ---
        func loadCSV(_ name: String) throws -> [[String: String]] {
            let text = try String(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(name),
                                  encoding: .utf8)
            let lines = text.split(separator: "\n")
            let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return lines.dropFirst().map { line in
                let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                return Dictionary(uniqueKeysWithValues: zip(header, cells))
            }
        }
        let feat = try loadCSV("features.csv")
        let stemRows = try loadCSV("stems.csv")
        var stemsByFrame: [String: [String: String]] = [:]
        for r in stemRows { if let fr = r["frame"] { stemsByFrame[fr] = r } }
        func fv(_ r: [String: String], _ k: String) -> Float { Float(r[k] ?? "") ?? 0 }

        // segment on track_elapsed_s reset
        var segs: [[[String: String]]] = []
        var cur: [[String: String]] = []
        var prev: Float?
        for r in feat {
            let te = fv(r, "track_elapsed_s")
            if let p = prev, te < p - 0.5 { segs.append(cur); cur = [] }
            cur.append(r); prev = te
        }
        if !cur.isEmpty { segs.append(cur) }
        guard segIdx < segs.count else { return XCTFail("segment \(segIdx) out of range") }
        let seg = segs[segIdx].filter { Double(fv($0, "track_elapsed_s")) >= lo
                                     && Double(fv($0, "track_elapsed_s")) <= hi }
        XCTAssertGreaterThan(seg.count, 30, "window too small")

        // --- Build the live pipeline once ---
        let context = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: Self.renderWidth, height: Self.renderHeight)
        let particles = try XCTUnwrap(FerrofluidParticles(device: device, library: shaderLibrary.library))
        particles.bakeHeightField(commandQueue: context.commandQueue)
        var baseUniforms = preset.descriptor.makeSceneUniforms()
        baseUniforms.sceneParamsA.y = Float(Self.renderWidth) / Float(Self.renderHeight)
        let baseLightIntensity = baseUniforms.lightPositionAndIntensity.w
        let baseLightColor = SIMD3(baseUniforms.lightColor.x, baseUniforms.lightColor.y,
                                   baseUniforms.lightColor.z)
        let baseFogFar = baseUniforms.sceneParamsB.y
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

        // --- CPU-side modulation state (mirrors applyAudioModulation) ---
        var smoothedLight: Float = 1.0
        var auroraSmoothed: Float = 0
        var auroraWarmup: Float = 1.0   // mid-track window: warmup long done
        var dollyOffset: Float = 0

        struct FrameStat { let te: Float; let mean: Float; let p99: Float; let whiteFrac: Float }
        var stats: [FrameStat] = []
        var prevPixels: [UInt8]?
        var maxBlockDelta: [(te: Float, delta: Float)] = []

        for r in seg {
            let te = fv(r, "track_elapsed_s")
            let dt = max(0.001, min(0.1, fv(r, "deltaTime")))
            var features = FeatureVector(
                bass: fv(r, "bass"), mid: fv(r, "mid"), treble: fv(r, "treble"),
                subBass: fv(r, "subBass"), lowBass: fv(r, "lowBass"), lowMid: fv(r, "lowMid"),
                midHigh: fv(r, "midHigh"), highMid: fv(r, "highMid"), high: fv(r, "high"),
                beatBass: fv(r, "beatBass"), beatMid: fv(r, "beatMid"),
                beatTreble: fv(r, "beatTreble"), beatComposite: fv(r, "beatComposite"),
                valence: fv(r, "valence"), arousal: fv(r, "arousal"),
                time: te, deltaTime: dt,
                accumulatedAudioTime: fv(r, "accumulatedAudioTime"))
            features.trackElapsedS = te
            features.pulsePhase01 = fv(r, "pulse_phase01")
            features.pulseAmp01 = ablate == "pulse" ? 0 : fv(r, "pulse_amp01")

            var stems = StemFeatures.zero
            if let srow = stemsByFrame[r["frame"] ?? ""] {
                stems.drumsEnergyDev = fv(srow, "drumsEnergyDev")
                stems.bassEnergyDev = fv(srow, "bassEnergyDev")
                stems.vocalsEnergyDev = fv(srow, "vocalsEnergyDev")
                stems.otherEnergyDev = fv(srow, "otherEnergyDev")
                stems.drumsEnergy = fv(srow, "drumsEnergy")
                stems.bassEnergy = fv(srow, "bassEnergy")
                stems.vocalsEnergy = fv(srow, "vocalsEnergy")
                stems.otherEnergy = fv(srow, "otherEnergy")
            }
            // -- replicate applyAudioModulation with the CSV's deterministic dt --
            var uniforms = baseUniforms
            let bassContribution = max(0, min(1.1, features.bass * 1.1))
            dollyOffset += dt * pipeline.cameraDollySpeed * (0.5 + bassContribution)
            uniforms.cameraOriginAndFov.z += dollyOffset
            let bassPrimary = max(0, min(1.0, features.bass))
            let beatAccent = max(0, min(1.0, max(features.beatBass,
                                                 max(features.beatMid, features.beatComposite))))
            smoothedLight = RayMarchPipeline.smoothLightIntensity(
                previous: smoothedLight, target: 1.0 + bassPrimary * 0.4 + beatAccent * 0.15, dt: dt)
            uniforms.lightPositionAndIntensity.w = ablate == "light"
                ? baseLightIntensity : baseLightIntensity * smoothedLight
            let warm = max(0, min(1, features.valence))
            let cool = max(0, min(1, -features.valence))
            let tint = SIMD3<Float>(1.0 + warm * 0.40 - cool * 0.25,
                                    1.0 + warm * 0.15 - cool * 0.10,
                                    1.0 + cool * 0.40 - warm * 0.30)
            uniforms.lightColor = SIMD4(baseLightColor * tint, 0)
            let arousal = max(-1, min(1, features.arousal))
            uniforms.sceneParamsB.y = baseFogFar * (arousal >= 0 ? 1 - arousal * 0.7 : 1 - arousal)
            uniforms.sceneParamsA.x = features.accumulatedAudioTime
            let aurora = RenderPipeline.auroraDriverStep(
                smoothed: auroraSmoothed, warmup01: auroraWarmup,
                drumsDev: stems.drumsEnergyDev, dt: dt)
            auroraSmoothed = aurora.smoothed
            auroraWarmup = aurora.warmup01
            stems.drumsEnergyDevSmoothed = ablate == "aurora" ? 0 : aurora.output
            pipeline.sceneUniforms = uniforms

            let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
            pipeline.render(gbufferPipelineState: gbufferState, features: &features,
                            fftBuffer: fftBuf, waveformBuffer: wavBuf, stemFeatures: stems,
                            outputTexture: outTex, commandBuffer: cmdBuf, noiseTextures: nil,
                            iblManager: iblManager, postProcessChain: ppChain,
                            presetFragmentBuffer3: nil,
                            presetHeightTexture: particles.heightTexture)
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()

            var pixels = [UInt8](repeating: 0, count: Self.renderWidth * Self.renderHeight * 4)
            outTex.getBytes(&pixels, bytesPerRow: Self.renderWidth * 4,
                            from: MTLRegionMake2D(0, 0, Self.renderWidth, Self.renderHeight),
                            mipmapLevel: 0)
            var sum: Float = 0
            var lumas: [Float] = []
            lumas.reserveCapacity(Self.renderWidth * Self.renderHeight / 16)
            var white = 0
            var n = 0
            for y in stride(from: 0, to: Self.renderHeight, by: 2) {
                for x in stride(from: 0, to: Self.renderWidth, by: 2) {
                    let i = (y * Self.renderWidth + x) * 4
                    let l = 0.114 * Float(pixels[i]) + 0.587 * Float(pixels[i + 1])
                          + 0.299 * Float(pixels[i + 2])
                    sum += l; lumas.append(l); n += 1
                    if l > 240 { white += 1 }
                }
            }
            lumas.sort()
            stats.append(FrameStat(te: te, mean: sum / Float(n),
                                   p99: lumas[Int(0.99 * Float(lumas.count - 1))],
                                   whiteFrac: Float(white) / Float(n)))
            // max 30x30-block delta vs previous frame (localised flash detector)
            if let prev = prevPixels {
                var maxDelta: Float = 0
                let bw = 30, bh = 30
                for by in 0..<(Self.renderHeight / bh) {
                    for bx in 0..<(Self.renderWidth / bw) {
                        var d: Float = 0
                        var c = 0
                        for y in stride(from: by * bh, to: (by + 1) * bh, by: 3) {
                            for x in stride(from: bx * bw, to: (bx + 1) * bw, by: 3) {
                                let i = (y * Self.renderWidth + x) * 4
                                let l1 = 0.114 * Float(pixels[i]) + 0.587 * Float(pixels[i + 1])
                                       + 0.299 * Float(pixels[i + 2])
                                let l0 = 0.114 * Float(prev[i]) + 0.587 * Float(prev[i + 1])
                                       + 0.299 * Float(prev[i + 2])
                                d += abs(l1 - l0); c += 1
                            }
                        }
                        maxDelta = max(maxDelta, d / Float(c))
                    }
                }
                maxBlockDelta.append((te, maxDelta))
            }
            prevPixels = pixels
        }

        // --- Report: frame-step events in the RENDERED output ---
        // Aggregate step metric for ablation comparison: count + total |dMean|>6.
        var stepCount = 0
        var stepSum: Float = 0
        for (a, b) in zip(stats, stats.dropFirst()) where abs(b.mean - a.mean) > 6 {
            stepCount += 1; stepSum += abs(b.mean - a.mean)
        }
        print("[FLASH-FORENSICS] window seg\(segIdx) \(lo)-\(hi)s frames=\(stats.count) "
              + "ablate=\(ablate) flashSteps(|dMean|>6)=\(stepCount) totalMag=\(stepSum)")
        for (a, b) in zip(stats, stats.dropFirst()) {
            let dMean = b.mean - a.mean
            let dWhite = b.whiteFrac - a.whiteFrac
            if abs(dMean) > 8 || dWhite > 0.01 {
                print(String(format: "[FLASH-FORENSICS] te=%.2f dMeanLuma=%+.1f white%%=%.2f→%.2f p99=%.0f→%.0f",
                             b.te, dMean, a.whiteFrac * 100, b.whiteFrac * 100, a.p99, b.p99))
            }
        }
        let topBlocks = maxBlockDelta.sorted { $0.delta > $1.delta }.prefix(8)
        for e in topBlocks {
            print(String(format: "[FLASH-FORENSICS] localised: te=%.2f maxBlockDelta=%.1f", e.te, e.delta))
        }
    }
}
