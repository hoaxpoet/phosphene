// RosetteMVWarpAccumulationTest — the permanent multi-frame harness for Rosette
// (adapted at WHIT.1c from the WHIT.0 look-spike's RosetteLookSpikeTests.swift, per
// PRESET_SESSION_CHECKLIST Part 2 / ROSETTE_DESIGN.md §10 item 4).
//
// Now that Rosette is registered (PhospheneEngine/Sources/Presets/Shaders/Rosette.*),
// this loads it from the real shipped bundle via `_acceptanceFixture`
// (PresetAcceptanceTests.swift) — the exact pattern AuroraVeilMVWarpAccumulationTest
// uses for an already-shipped preset — instead of WHIT.0's `watchDirectory` scratch-dir
// mechanism, which existed only because Rosette wasn't registered yet.
//
// Exercises the real production dispatch for a marks-on-top preset: Pass 1 warps the
// previous held frame (`mvWarp_vertex`/`mvWarp_fragment`, identity per Rosette.metal's
// `mvWarpPerVertex`); Pass 2 draws the geometry overlay directly onto that warped
// texture with normal-alpha blend — the `strandsOnTop` path every preset with a
// scene-geometry overlay takes (RenderPipeline+MVWarp.swift:138); then swap.
//
// Two tests:
//   - test_rosette_multiFrameNonDegenerate — ALWAYS RUNS (no env gate). Regression
//     guard: renders frames at several points across the morph and asserts (a) each
//     frame is non-degenerate (real luma variance, not a flat fill) and (b) frames at
//     different clock times actually differ from each other. (b) is a direct regression
//     guard against WHIT.0's own found bug — a broken FeatureVector fragment binding
//     made every frame render the same fixed mid-morph shape regardless of `time`.
//   - test_rosette_visualDump — env-gated (ROSETTE_MVWARP_DIAG=1), for human tuning:
//     dumps a 300-frame motion_gate.sh sequence + hi-res named-state stills, same as
//     WHIT.0's spike test.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Rosette mv_warp multi-frame harness")
struct RosetteMVWarpAccumulationTest {

    private static let seqWidth = 960
    private static let seqHeight = 540
    private static let hiWidth = 1920
    private static let hiHeight = 1080

    // Must match Rosette.metal's kRosetteAMin / kRosetteAMax / kRosettePeriod
    // (triangle-wave morph clock — constant rate, no easing, §9.4).
    private static let aMin: Double = 0.05
    private static let aMax: Double = 1.80
    private static let period: Double = 30.0

    private static func timeForA(_ a: Double) -> Double {
        let tri = max(0.0, min(1.0, (a - aMin) / (aMax - aMin)))
        return tri * period / 2.0
    }

    // MARK: - Always-on regression guard

    @Test("Rosette: multi-frame render is non-degenerate and clock-sensitive")
    func test_rosette_multiFrameNonDegenerate() throws {
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture — is it registered?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()
        // Five points across the morph: pentagon, star, petals, tangle, and back near pentagon.
        let times = [0.15, 0.30, 0.75, 1.80, 0.20].map { Self.timeForA($0) }
        var frames: [[UInt8]] = []
        for t in times {
            let pixels = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                             width: Self.seqWidth, height: Self.seqHeight, time: t)
            frames.append(pixels)
        }

        // (a) non-degenerate: real luma variance, not a flat fill.
        for (i, pixels) in frames.enumerated() {
            let (minL, maxL) = lumaRange(pixels)
            #expect(maxL - minL > 20,
                    "Rosette frame \(i) (t=\(times[i])) is degenerate — luma range \(minL)-\(maxL), expected a visible stroke")
        }

        // (b) clock-sensitive: frames at different morph states must differ from each
        // other. This is the direct regression guard for WHIT.0's found bug — a broken
        // FeatureVector fragment binding rendered every frame as the same fixed shape.
        for i in 1..<frames.count {
            let diff = meanAbsDiff(frames[i - 1], frames[i])
            #expect(diff > 2.0,
                    "Rosette frames \(i - 1) and \(i) (t=\(times[i-1]) vs \(times[i])) are near-identical (meanAbsDiff=\(diff)) — the morph clock may not be reaching the fragment")
        }
    }

    // MARK: - WHIT.1d: harmony coupling regression guard

    @Test("Rosette: tonalConsonance sets figure tightness; bassDev boosts stroke presence")
    func test_rosette_harmonyCoupling() throws {
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture — is it registered?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()
        let t0 = Self.period / 4.0   // clock alone sits near the loose/tangle end here

        // (a) High consonance (p99, ~full presence) must override the clock and pull the
        // figure toward the TIGHT end, regardless of what the clock alone would show at t0.
        let atFloor = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                          width: Self.seqWidth, height: Self.seqHeight, time: t0, consonance: 0.0)
        let atP99 = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                        width: Self.seqWidth, height: Self.seqHeight, time: t0, consonance: 0.32)
        let diff = meanAbsDiff(atFloor, atP99)
        #expect(diff > 5.0,
                "Rosette at t0=\(t0): consonance 0.0 vs 0.32 renders are near-identical (meanAbsDiff=\(diff)) — tonalConsonance may not be reaching the tightness mapping")

        // (b) bassDev boosts overall brightness (stroke_presence) at fixed time+consonance.
        let dim = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                      width: Self.seqWidth, height: Self.seqHeight, time: t0, consonance: 0.15, bassDev: 0.0)
        let bright = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                         width: Self.seqWidth, height: Self.seqHeight, time: t0, consonance: 0.15, bassDev: 1.0)
        // Mean, not peak — the stroke's core already saturates to 255 regardless of the
        // presence boost, so peak luma can't distinguish the two; the boosted halo widens
        // and lifts the frame's overall brightness instead.
        let dimMean = meanLuma(dim)
        let brightMean = meanLuma(bright)
        #expect(brightMean > dimMean,
                "Rosette bassDev=1.0 mean luma (\(brightMean)) is not brighter than bassDev=0.0 (\(dimMean)) — stroke_presence may not be reaching bassDev")
    }

    // MARK: - BUG-104: curve-continuity regression guard

    @Test("Rosette: the tangle-state curve renders as one continuous stroke, no branch-lock gaps (BUG-104)")
    func test_rosette_curveIsContinuousAtHighA() throws {
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture — is it registered?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()
        // The tangle state (a=1.80) is where rosetteDist's coarse-then-bisect search used
        // to lock onto the single globally-closest coarse sample and never consider a
        // different, ultimately-closer curve branch — visible live as literal gaps in the
        // stroke (Matt: "Lines do not connect. The motion is all wrong."). Measured
        // directly against the pre-fix render: bright-pixel coverage was 5.92% of the
        // frame (gappy); fixed (checking all local minima among the coarse samples, not
        // just the global one) it is 6.96%. 6.3% sits with margin on both sides.
        let pixels = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                         width: Self.hiWidth, height: Self.hiHeight, time: Self.period / 2.0)
        let fraction = brightPixelFraction(pixels, threshold: 100)
        #expect(fraction > 0.063,
                "Rosette tangle-state (a=1.80) bright-pixel coverage \(String(format: "%.4f", fraction)) is at or below the pre-fix (gappy) measurement of 0.0592 — rosetteDist may be locking onto a single curve branch again (BUG-104)")
    }

    // MARK: - BUG-103: wing visibility at non-16:9 aspect regression guard

    @Test("Rosette: wing arcs stay on-screen at a near-square aspect (BUG-103)")
    func test_rosette_wingsVisibleAtNearSquareAspect() throws {
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture — is it registered?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()
        // Matt's live session 2026-08-26T12-58-21Z rendered at exactly this size (aspect
        // 1.061) — the wing arcs vanished off-screen entirely (BUG-103). Independently
        // derive the expected wing column band from Rosette.metal's own fix formula
        // (kRosetteReferenceAspect = 16/9, wing x in [0.62, 0.67] pre-scale) so this test
        // catches a regression rather than re-asserting the implementation.
        let width = 1080, height = 1018
        let aspect = Double(width) / Double(height)
        let xScale = aspect / (16.0 / 9.0)
        let xLo = xScale * 0.62, xHi = xScale * 0.67
        func columnBand(side: Double) -> (Int, Int) {
            let uvLo = 0.5 + side * xLo / aspect, uvHi = 0.5 + side * xHi / aspect
            let cols = [uvLo, uvHi].map { Int(($0 * Double(width)).rounded()) }.sorted()
            return (max(0, cols[0] - 20), min(width - 1, cols[1] + 20))
        }
        let (rightLo, rightHi) = columnBand(side: 1.0)
        let (leftLo, leftHi) = columnBand(side: -1.0)

        let pixels = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                         width: width, height: height, time: Self.timeForA(0.30))
        let rightBandMax = maxLumaInColumnRange(pixels, width: width, height: height, colLo: rightLo, colHi: rightHi)
        let leftBandMax = maxLumaInColumnRange(pixels, width: width, height: height, colLo: leftLo, colHi: leftHi)
        // Near-black ground reads well under 40/255 after the sRGB encode (WHIT.0/1c
        // tuning, ROSETTE_DESIGN.md §6.5); a visible wing arc or ellipse is a saturated
        // hue swatch that reads far brighter.
        #expect(rightBandMax > 60,
                "Rosette at \(width)x\(height) (aspect \(aspect)): right wing column band [\(rightLo),\(rightHi)] max luma \(rightBandMax) reads as background-only — the wing may be off-screen again (BUG-103)")
        #expect(leftBandMax > 60,
                "Rosette at \(width)x\(height) (aspect \(aspect)): left wing column band [\(leftLo),\(leftHi)] max luma \(leftBandMax) reads as background-only — the wing may be off-screen again (BUG-103)")
    }

    // MARK: - WHIT.1d-2: rotation + symmetry-step regression guard

    @Test("Rosette: tonalPhaseFifths rotates the figure; harmonicFlux steps the symmetry order")
    func test_rosette_rotationAndSymmetryCoupling() throws {
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture — is it registered?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()
        let t0 = Self.timeForA(0.30)   // a state with plenty of visible figure detail (star)

        // (a) morph_position <- tonalPhaseFifths: a quarter-turn rotation must visibly move
        // the figure. `RosetteState` seeds fully (no smoothing lag) on its first tick, so a
        // fresh single-frame state directly reflects the value passed in.
        let unrotated = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                            width: Self.seqWidth, height: Self.seqHeight, time: t0,
                                            consonance: 0.15, tonalPhaseFifths: 0)
        let rotated = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                          width: Self.seqWidth, height: Self.seqHeight, time: t0,
                                          consonance: 0.15, tonalPhaseFifths: .pi / 2)
        let rotDiff = meanAbsDiff(unrotated, rotated)
        #expect(rotDiff > 2.0,
                "Rosette at t0=\(t0): tonalPhaseFifths=0 vs pi/2 renders are near-identical (meanAbsDiff=\(rotDiff)) — morph_position may not be reaching the figure rotation")

        // (b) symmetry_order_step <- harmonicFlux: a qualifying spike (RosetteState starts
        // with timeSinceLastStep == minHoldSeconds, so the very first tick's spike steps
        // immediately) must change the figure's symmetry order (5-fold -> 6-fold).
        let orderFive = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                            width: Self.seqWidth, height: Self.seqHeight, time: t0,
                                            consonance: 0.15, harmonicFlux: 0)
        let orderSix = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                           width: Self.seqWidth, height: Self.seqHeight, time: t0,
                                           consonance: 0.15, harmonicFlux: 1.0)
        let stepDiff = meanAbsDiff(orderFive, orderSix)
        #expect(stepDiff > 2.0,
                "Rosette at t0=\(t0): harmonicFlux=0 (5-fold) vs 1.0 (steps to 6-fold) renders are near-identical (meanAbsDiff=\(stepDiff)) — symmetry_order_step may not be reaching rosetteDist's n")
    }

    // MARK: - Env-gated visual dump (human tuning)

    @Test("Rosette: visual dump for motion_gate.sh / human review (env-gated)")
    func test_rosette_visualDump() throws {
        guard ProcessInfo.processInfo.environment["ROSETTE_MVWARP_DIAG"] == "1" else {
            print("RosetteMVWarpAccumulationTest: ROSETTE_MVWARP_DIAG not set, skipping")
            return
        }
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            Issue.record("Rosette preset not found in _acceptanceFixture")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let ctx = try MetalContext()

        let seqDir = try makeOutputDir("rosette_mvwarp_seq")
        print("[rosette-diag] sequence output dir: \(seqDir.path)")
        let seqTimes = (0..<300).map { 0.1 * Double($0) }
        try renderFrames(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                          width: Self.seqWidth, height: Self.seqHeight,
                          times: seqTimes, outDir: seqDir, namePrefix: "rosette_seq")

        let stillsDir = try makeOutputDir("rosette_mvwarp_stills")
        print("[rosette-diag] stills output dir: \(stillsDir.path)")
        let targets: [(String, Double)] = [
            ("pentagon_a015", Self.timeForA(0.15)),
            ("star_a030", Self.timeForA(0.30)),
            ("petals_a075", Self.timeForA(0.75)),
            ("tangle_a180", Self.period / 2.0),
        ]

        // WHIT.1d: harmony-coupling comparison, same wall time, consonance only.
        let harmonyDir = try makeOutputDir("rosette_harmony")
        print("[rosette-diag] harmony coupling output dir: \(harmonyDir.path)")
        let tFixed = Self.period / 4.0
        for (name, c) in [("floor_c000", Float(0.0)), ("median_c0117", Float(0.117)), ("p99_c032", Float(0.32))] {
            let pixels = try renderOneFrame(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                                             width: Self.hiWidth, height: Self.hiHeight, time: tFixed, consonance: c)
            try writePNG(pixels, width: Self.hiWidth, height: Self.hiHeight,
                         to: harmonyDir.appendingPathComponent("\(name).png"))
        }
        for (name, t) in targets {
            try renderFrames(preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                              width: Self.hiWidth, height: Self.hiHeight,
                              times: Array(repeating: t, count: 4), outDir: stillsDir,
                              namePrefix: name, keepAllFrames: false)
        }
        print("[rosette-diag] done.")
    }

    // MARK: - Single-frame render (fresh textures each call — for the regression guard)

    private func renderOneFrame(
        preset: PresetLoader.LoadedPreset, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        geo: MTLRenderPipelineState, context: MetalContext, width: Int, height: Int, time: Double,
        consonance: Float = 0, bassDev: Float = 0, midAttRel: Float = 0,
        tonalPhaseFifths: Float = 0, harmonicFlux: Float = 0
    ) throws -> [UInt8] {
        let device = context.device
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let warpTex = device.makeTexture(descriptor: texDesc),
              let composeTex = device.makeTexture(descriptor: texDesc)
        else { throw DiagError.textureFailed }
        try HarnessTemplateCore.clear([warpTex, composeTex], context)

        var features = FeatureVector(time: Float(time), deltaTime: 1.0 / 60.0)
        features.aspectRatio = Float(width) / Float(height)
        features.tonalConsonance = consonance
        features.bassDev = bassDev
        features.midAttRel = midAttRel
        features.tonalPhaseFifths = tonalPhaseFifths
        features.harmonicFlux = harmonicFlux
        // WHIT.1d-2: the geometry fragment now reads RosetteState's uniforms at buffer(6)
        // (smoothedFifths rotation, held symmetryN) — an unbound slot here reads undefined
        // GPU memory, the same class of bug chromaticMix hit at WHIT.0. A fresh state per
        // call + a single tick means the smoother is seeded straight from this call's
        // `tonalPhaseFifths` (no cross-frame carryover to worry about in a single-frame test).
        guard let state = RosetteState(device: device) else { throw DiagError.textureFailed }
        state.tick(deltaTime: 1.0 / 60.0, features: features)
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw DiagError.cmdBufferFailed }
        try encodeWarp(cmd: cmd, mvWarp: mvWarp, warpTex: warpTex, composeTex: composeTex, features: &features)
        try encodeGeometryOverlay(cmd: cmd, geo: geo, target: composeTex, features: &features, state: state)
        cmd.commit()
        cmd.waitUntilCompleted()
        return try readPixels(from: composeTex, width: width, height: height)
    }

    // MARK: - Frame loop (warp -> geometry overlay onto warped tex -> swap), for the visual dump

    private func renderFrames(
        preset: PresetLoader.LoadedPreset, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        geo: MTLRenderPipelineState, context: MetalContext, width: Int, height: Int,
        times: [Double], outDir: URL, namePrefix: String, keepAllFrames: Bool = true
    ) throws {
        let device = context.device
        let queue = context.commandQueue
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: texDesc),
              var composeTex = device.makeTexture(descriptor: texDesc)
        else { throw DiagError.textureFailed }
        try HarnessTemplateCore.clear([warpTex, composeTex], context)
        guard let state = RosetteState(device: device) else { throw DiagError.textureFailed }

        for (idx, t) in times.enumerated() {
            var features = FeatureVector(time: Float(t), deltaTime: 1.0 / 60.0)
            features.aspectRatio = Float(width) / Float(height)
            state.tick(deltaTime: 1.0 / 60.0, features: features)
            guard let cmd = queue.makeCommandBuffer() else { throw DiagError.cmdBufferFailed }
            try encodeWarp(cmd: cmd, mvWarp: mvWarp, warpTex: warpTex, composeTex: composeTex, features: &features)
            try encodeGeometryOverlay(cmd: cmd, geo: geo, target: composeTex, features: &features, state: state)
            cmd.commit()
            cmd.waitUntilCompleted()
            let tmp = warpTex; warpTex = composeTex; composeTex = tmp

            if keepAllFrames || idx == times.count - 1 {
                let pixels = try readPixels(from: warpTex, width: width, height: height)
                let url = outDir.appendingPathComponent(String(format: "%@_%04d.png", namePrefix, idx))
                try writePNG(pixels, width: width, height: height, to: url)
            }
        }
    }

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture, features: inout FeatureVector
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw DiagError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.warpState)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stemsCopy = StemFeatures.zero
        enc.setVertexBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = SceneUniforms()
        enc.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        enc.setFragmentTexture(warpTex, index: 0)
        // mvWarp_fragment's fragment buffer(0) is `chromaticMix` (PresetLoader+WarpPreamble.swift:155),
        // NOT the vertex-slot FeatureVector — an unbound slot here reads undefined GPU
        // memory and drives a runaway hue-zoom resample feedback loop (WHIT.0 finding).
        // Rosette.json's marks.chromatic is 0.0 — bind that explicitly (identity).
        var chromaticMix: Float = 0.0
        enc.setFragmentBytes(&chromaticMix, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31x23 grid (AuroraVeil template)
        enc.endEncoding()
    }

    private func encodeGeometryOverlay(
        cmd: MTLCommandBuffer, geo: MTLRenderPipelineState, target: MTLTexture, features: inout FeatureVector,
        state: RosetteState
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load     // keep the warped frame (strandsOnTop contract)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw DiagError.encoderFailed }
        enc.setRenderPipelineState(geo)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stemsCopy = StemFeatures.zero
        enc.setVertexBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.stride, index: 1)
        // WHIT.1d-2: RosetteState's uniforms (smoothedFifths rotation, held symmetryN) —
        // fragment buffer(6), Skein's per-preset-uniforms convention.
        enc.setFragmentBuffer(state.rosetteBuffer, offset: 0, index: 6)
        // Rosette.json marks: vertex_count 3 / instance_count 1 / primitive "triangle"
        // (fullscreen-triangle overlay — all figure math is per-pixel in the fragment).
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        enc.endEncoding()
    }

    // MARK: - Helpers

    private func readPixels(from tex: MTLTexture, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&pixels, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    private func lumaRange(_ pixels: [UInt8]) -> (Float, Float) {
        var minL: Float = 255, maxL: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = Float(pixels[i]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
            let luma = 0.114 * b + 0.587 * g + 0.299 * r
            if luma < minL { minL = luma }
            if luma > maxL { maxL = luma }
        }
        return (minL, maxL)
    }

    private func maxLumaInColumnRange(_ pixels: [UInt8], width: Int, height: Int, colLo: Int, colHi: Int) -> Float {
        var maxL: Float = 0
        for row in 0..<height {
            for col in colLo...colHi {
                let i = (row * width + col) * 4
                let b = Float(pixels[i]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
                let luma = 0.114 * b + 0.587 * g + 0.299 * r
                if luma > maxL { maxL = luma }
            }
        }
        return maxL
    }

    private func brightPixelFraction(_ pixels: [UInt8], threshold: Float) -> Double {
        var count = 0
        var n = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = Float(pixels[i]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
            let luma = 0.114 * b + 0.587 * g + 0.299 * r
            if luma > threshold { count += 1 }
            n += 1
        }
        return Double(count) / Double(n)
    }

    private func meanLuma(_ pixels: [UInt8]) -> Double {
        var sum: Double = 0
        var n = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = Double(pixels[i]), g = Double(pixels[i + 1]), r = Double(pixels[i + 2])
            sum += 0.114 * b + 0.587 * g + 0.299 * r
            n += 1
        }
        return sum / Double(n)
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum: Double = 0
        for i in 0..<a.count { sum += Double(abs(Int(a[i]) - Int(b[i]))) }
        return sum / Double(a.count)
    }

    private func makeOutputDir(_ name: String) throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/\(name)/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(_ pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        var rgba = [UInt8](repeating: 0, count: pixels.count)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            rgba[i + 0] = pixels[i + 2]
            rgba[i + 1] = pixels[i + 1]
            rgba[i + 2] = pixels[i + 0]
            rgba[i + 3] = pixels[i + 3]
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: width, height: height,
                                bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4,
                                space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)
        else { throw DiagError.encoderFailed }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw DiagError.encoderFailed
        }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

private enum DiagError: Error {
    case textureFailed
    case cmdBufferFailed
    case encoderFailed
}
