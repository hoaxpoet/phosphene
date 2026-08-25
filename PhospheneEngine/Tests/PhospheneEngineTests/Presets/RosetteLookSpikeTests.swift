// RosetteLookSpikeTests — WHIT.0 multi-frame harness, adapted from
// AuroraVeilMVWarpAccumulationTest (QG.4/D-182) per PRESET_SESSION_CHECKLIST Part 2:
// "written or extended before any shader work."
//
// THROWAWAY spike test. Loads Rosette.metal/.json from
// Tests/PhospheneEngineTests/Presets/Fixtures/Rosette/ via PresetLoader's
// `watchDirectory` scratch-dir mechanism (the exact pattern PresetLoaderTests.swift
// uses throughout) — never touches the shipped Sources/Presets/Shaders/ directory,
// so preset count and app registration are unaffected (WHIT.0 pre-flight #6).
//
// Exercises the REAL production dispatch for a marks-on-top preset: Pass 1 warps the
// previous held frame (`mvWarp_vertex`/`mvWarp_fragment`, identity per
// Rosette.metal's `mvWarpPerVertex`); Pass 2 draws the geometry overlay directly onto
// that warped texture with normal-alpha blend — the `strandsOnTop` path every preset
// with a scene-geometry overlay takes (RenderPipeline+MVWarp.swift:138, "the
// standard / Dragon-Bloom / Skein mv_warp pass chain"); then swap. This is the same
// dispatch code DragonBloom/Skein run live, just driven by hand here instead of
// through RenderPipeline/MTKView, because the preset is intentionally NOT registered.
//
// Env-gated like its template — WHIT0_ROSETTE_SPIKE=1 — so it never runs in CI.
// Frames land under /tmp/whit0_rosette_*/<ISO>/ for Scripts/motion_gate.sh and
// direct visual reading (D-064 — the reader is Claude's eyes, no auto-pass).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("WHIT.0 Rosette look-spike (env-gated)")
struct RosetteLookSpikeTests {

    private static let seqWidth = 960
    private static let seqHeight = 540
    private static let hiWidth = 1920
    private static let hiHeight = 1080

    // Must match Rosette.metal's kRosetteAMin / kRosetteAMax / kRosettePeriod
    // (triangle-wave morph clock, not sine — constant rate, no easing, §9.4).
    private static let aMin: Double = 0.05
    private static let aMax: Double = 1.80
    private static let period: Double = 30.0

    /// Inverts the triangle wave on the RISING half only — picks the first t in
    /// [0, period/2] where a(t) == target.
    private static func timeForA(_ a: Double) -> Double {
        let tri = max(0.0, min(1.0, (a - aMin) / (aMax - aMin)))
        return tri * period / 2.0
    }

    @Test("Render the WHIT.0 motion_gate sequence + hi-res comparison stills")
    func test_rosetteSpike_render() throws {
        guard ProcessInfo.processInfo.environment["WHIT0_ROSETTE_SPIKE"] == "1" else {
            print("RosetteLookSpikeTests: WHIT0_ROSETTE_SPIKE not set, skipping")
            return
        }
        let ctx = try MetalContext()
        // Same device for the loader and the harness's own textures/encoders —
        // pipeline states are device-bound, so mixing devices here would crash.
        let preset = try loadRosettePreset(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let mvWarp = preset.mvWarpPipelines, let geo = mvWarp.sceneGeometryState else {
            Issue.record("Rosette preset compiled with no scene-geometry overlay pipeline — check Rosette.metal for rosette_geometry_vertex/_fragment")
            return
        }

        // ── 300-frame contiguous sequence, one full 30s tighten/unravel cycle,
        //    dt=0.1s → exactly one morph period → motion_gate.sh input. ──
        let seqDir = try makeOutputDir("whit0_rosette_seq")
        print("[whit0] sequence output dir: \(seqDir.path)")
        let seqTimes = (0..<300).map { 0.1 * Double($0) }
        try renderFrames(
            preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
            width: Self.seqWidth, height: Self.seqHeight,
            times: seqTimes, outDir: seqDir, namePrefix: "rosette_seq"
        )

        // ── Hi-res stills at named morph states (task 1/2/4/5 comparisons) ──
        let stillsDir = try makeOutputDir("whit0_rosette_stills")
        print("[whit0] stills output dir: \(stillsDir.path)")
        let targets: [(String, Double)] = [
            ("pentagon_a015", Self.timeForA(0.15)),
            ("star_a030", Self.timeForA(0.30)),
            ("petals_a075", Self.timeForA(0.75)),
            ("tangle_a180", Self.period / 2.0)   // triangle peak == a = aMax = 1.80
        ]
        for (name, t) in targets {
            // Render a few settle frames at the SAME frozen time then keep the last —
            // decay is near-moot (the fragment repaints opaque every frame) but this
            // costs nothing and removes any doubt about first-frame warp-texture zero-init.
            let settleTimes = Array(repeating: t, count: 4)
            try renderFrames(
                preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
                width: Self.hiWidth, height: Self.hiHeight,
                times: settleTimes, outDir: stillsDir, namePrefix: name, keepAllFrames: false
            )
        }
        // ── Task 5: with/without the mirrored wing arcs, same morph moment ──
        let framingDir = try makeOutputDir("whit0_rosette_framing")
        print("[whit0] framing (with/without wings) output dir: \(framingDir.path)")
        let noWings = try loadRosettePreset(
            device: ctx.device, pixelFormat: ctx.pixelFormat,
            stem: "RosetteNoWings", presetName: "Rosette No-Wings (WHIT.0 spike)"
        )
        guard let noWingsMVWarp = noWings.mvWarpPipelines, let noWingsGeo = noWingsMVWarp.sceneGeometryState else {
            Issue.record("RosetteNoWings preset compiled with no scene-geometry overlay pipeline")
            return
        }
        let framingT = Self.timeForA(0.75)   // "petals" — a representative, non-degenerate morph moment
        try renderFrames(
            preset: preset, mvWarp: mvWarp, geo: geo, context: ctx,
            width: Self.hiWidth, height: Self.hiHeight,
            times: Array(repeating: framingT, count: 4), outDir: framingDir, namePrefix: "with_wings", keepAllFrames: false
        )
        try renderFrames(
            preset: noWings, mvWarp: noWingsMVWarp, geo: noWingsGeo, context: ctx,
            width: Self.hiWidth, height: Self.hiHeight,
            times: Array(repeating: framingT, count: 4), outDir: framingDir, namePrefix: "without_wings", keepAllFrames: false
        )
        print("[whit0] done.")
    }

    // MARK: - Preset loading (watchDirectory scratch-dir mechanism)

    private func loadRosettePreset(
        device: MTLDevice, pixelFormat: MTLPixelFormat,
        stem: String = "Rosette", presetName: String = "Rosette (WHIT.0 spike)"
    ) throws -> PresetLoader.LoadedPreset {
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // /Presets/
            .appendingPathComponent("Fixtures/Rosette", isDirectory: true)
        let metalSrc = fixturesDir.appendingPathComponent("\(stem).metal")
        let jsonSrc = fixturesDir.appendingPathComponent("\(stem).json")
        precondition(FileManager.default.fileExists(atPath: metalSrc.path), "\(stem).metal fixture missing")
        precondition(FileManager.default.fileExists(atPath: jsonSrc.path), "\(stem).json fixture missing")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whit0_rosette_scratch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: metalSrc, to: tempDir.appendingPathComponent("\(stem).metal"))
        try FileManager.default.copyItem(at: jsonSrc, to: tempDir.appendingPathComponent("\(stem).json"))

        // loadBuiltIn: false — isolates this loader from the shipped bundle entirely,
        // so nothing here touches expectedProductionPresetCount (PresetLoaderTests precedent).
        let loader = PresetLoader(
            device: device, pixelFormat: pixelFormat,
            watchDirectory: tempDir, loadBuiltIn: false
        )
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw DiagError.presetLoadFailed
        }
        return preset
    }

    // MARK: - Frame loop (warp -> geometry overlay onto warped tex -> swap)

    private func renderFrames(
        preset: PresetLoader.LoadedPreset,
        mvWarp: PresetLoader.MVWarpCompiledPipelines,
        geo: MTLRenderPipelineState,
        context: MetalContext,
        width: Int, height: Int,
        times: [Double],
        outDir: URL,
        namePrefix: String,
        keepAllFrames: Bool = true
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

        for (idx, t) in times.enumerated() {
            var features = FeatureVector(time: Float(t), deltaTime: 1.0 / 60.0)
            features.aspectRatio = Float(width) / Float(height)
            guard let cmd = queue.makeCommandBuffer() else { throw DiagError.cmdBufferFailed }

            // Pass 1: warp prev (warpTex) -> composeTex. Identity per mvWarpPerVertex.
            try encodeWarp(cmd: cmd, mvWarp: mvWarp, warpTex: warpTex, composeTex: composeTex, features: &features)

            // Pass 2: geometry overlay drawn DIRECTLY onto the warped composeTex
            // (strandsOnTop — RenderPipeline+MVWarp.swift:138/162-168). Normal alpha
            // blend; our fragment outputs alpha=1 everywhere so this fully replaces
            // the destination (matches Rosette.metal's "opaque every frame" contract).
            try encodeGeometryOverlay(cmd: cmd, geo: geo, target: composeTex, features: &features)

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
        // memory and drives a runaway hue-zoom resample feedback loop (found live: a
        // concentric-ring kaleidoscope artifact swamping the frame). Rosette.json's
        // marks.chromatic is 0.0 — bind that explicitly (identity, no resample).
        var chromaticMix: Float = 0.0
        enc.setFragmentBytes(&chromaticMix, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31x23 grid (per AuroraVeil template)
        enc.endEncoding()
    }

    private func encodeGeometryOverlay(
        cmd: MTLCommandBuffer, geo: MTLRenderPipelineState, target: MTLTexture, features: inout FeatureVector
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
        // Rosette.json marks: vertex_count 3 / instance_count 1 / primitive "triangle"
        // (fullscreen-triangle overlay, Skein's pattern — all figure math is per-pixel).
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
    case presetLoadFailed
}
