// RicercarFluidVideoHarness — RICERCAR-FL: the closest-to-real validation of the Fantasia drive.
//
// Matt's bar (2026-07-08): "the most important thing is how the visuals appear in RESPONSE to musical
// signals." A static contact sheet cannot show that. This harness runs a REAL track through the
// PRODUCTION analysis path (FFTProcessor → MIRPipeline for the zero-lag band/beat features;
// InstrumentFamilyAnalyzer for the family capture, StemFeatures 48–55), drives RicercarFluidGeometry
// with that real per-frame stream exactly as the live app does (`RenderPipeline+Draw`), renders every
// frame, and encodes an MP4 via ffmpeg. It is NOT synthetic (FA #27) — the only thing it does not
// reproduce is a live streaming session; the response to real music, in motion, is real.
//
// Env-gated (opt-in, like the dumpers — it shells out to ffmpeg and needs the PANNs model + a real
// audio file, none of which belong in the default CI run):
//   RICERCAR_VIDEO=1 [RICERCAR_AUDIO=/path/to/track] [RICERCAR_SECONDS=18] \
//     swift test --package-path PhospheneEngine --filter RicercarFluidVideoHarness
// Output: /tmp/ricercar_fluid_diag/ricercar_response_<track>.mp4  (+ the frames alongside).

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Audio
@testable import DSP
@testable import ML
@testable import Renderer
@testable import Shared

@Suite("Ricercar fluid — real-audio response video (env-gated)")
struct RicercarFluidVideoHarness {

    private enum E: Error { case setup, render, decode, encode }
    static let simW = 480, simH = 270
    static let outW = 960, outH = 540
    static let simFPS: Float = 60          // sim advances at production rate (texels/frame calibration)
    static let videoFPS = 30               // capture every 2nd sim frame

    @Test("Render Ricercar responding to a real analyzed track → MP4")
    func test_realAudioResponseVideo() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_VIDEO"] == "1" else {
            print("RicercarFluidVideoHarness: RICERCAR_VIDEO not set — skipping"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarFluidVideoHarness: no Metal device — skipping"); return
        }
        // Default to an in-repo fixture (resolved from this source file so cwd doesn't matter); point
        // RICERCAR_AUDIO at a corpus classical track for the family-colour path (pop/rock = motion only).
        let audioPath = env["RICERCAR_AUDIO"] ?? Self.defaultFixture()
        let seconds = Double(env["RICERCAR_SECONDS"] ?? "18") ?? 18
        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("RicercarFluidVideoHarness: audio not found at \(audioPath) — skipping"); return
        }

        // 1. Real MIR feature stream (zero-lag band deviations + beats), 60 fps, exactly the live cadence.
        let mirSR: Float = 48_000
        let mirSamples = try decodeMono(audioPath, sampleRate: Int(mirSR), seconds: seconds)
        let features = try mirFeatureStream(mirSamples, sampleRate: mirSR)
        print("[ricercar_video] MIR: \(features.count) frames @ \(Self.simFPS) fps from \(URL(fileURLWithPath: audioPath).lastPathComponent)")

        // 2. Real instrument-family series (best-effort — needs the PANNs model; motion works without it).
        let familySeries = familyStream(audioPath, seconds: seconds)
        print("[ricercar_video] family: \(familySeries.count) windows (empty = PANNs unavailable → motion-only)")

        // 3. Drive the geometry with the real stream, render every 2nd frame, write PNGs.
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try RicercarFluidGeometry(device: ctx.device, library: lib.library,
                                            width: Self.simW, height: Self.simH, pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx)
        let dir = try makeOutputDir()
        let frameDir = dir.appendingPathComponent("frames")
        try? FileManager.default.removeItem(at: frameDir)
        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

        let hop = InstrumentFamilyAnalyzer.hopSeconds
        var captured = 0
        for (i, fv) in features.enumerated() {
            // Sample the family series by playback position, exactly as VisualizerEngine+Audio does.
            var stem = StemFeatures.zero
            if !familySeries.isEmpty {
                let fam = InstrumentFamilyActivity.sample(
                    familySeries, atPlaybackSeconds: Double(i) / Double(Self.simFPS), hopSeconds: hop)
                let sm = fam.smoothedSIMD4, dv = fam.devSIMD4
                stem.stringsActivity = sm.x; stem.stringsActivityDev = dv.x
                stem.brassActivity = sm.y; stem.brassActivityDev = dv.y
                stem.woodwindsActivity = sm.z; stem.woodwindsActivityDev = dv.z
                stem.percussionActivity = sm.w; stem.percussionActivityDev = dv.w
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
            geo.update(features: fv, stemFeatures: stem, commandBuffer: cmd)
            let capture = (i % 2 == 0)
            if capture {
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = tex
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
                rpd.colorAttachments[0].storeAction = .store
                guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
                geo.render(encoder: enc, features: fv)
                enc.endEncoding()
            }
            cmd.commit(); cmd.waitUntilCompleted()
            if capture {
                var px = [UInt8](repeating: 0, count: Self.outW * Self.outH * 4)
                tex.getBytes(&px, bytesPerRow: Self.outW * 4,
                             from: MTLRegionMake2D(0, 0, Self.outW, Self.outH), mipmapLevel: 0)
                let url = frameDir.appendingPathComponent(String(format: "f%05d.png", captured))
                try writeBGRAToPNG(px, w: Self.outW, h: Self.outH, url: url)
                captured += 1
            }
        }
        print("[ricercar_video] wrote \(captured) frames")

        // 4. Encode MP4 (yuv420p for QuickTime).
        let stem = URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent
        let mp4 = dir.appendingPathComponent("ricercar_response_\(stem).mp4")
        try encodeMP4(frameDir: frameDir, fps: Self.videoFPS, out: mp4)
        print("[ricercar_video] MP4 → \(mp4.path)")
        #expect(captured > 0)
        #expect(FileManager.default.fileExists(atPath: mp4.path), "ffmpeg did not produce the MP4")
    }

    /// Repo-relative fixture resolved from this file's path (…/PhospheneEngine/Tests/PhospheneEngineTests/
    /// Diagnostics/ → up 4 → repo root), so the default works regardless of the test's working directory.
    private static func defaultFixture(file: String = #filePath) -> String {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // Diagnostics/PhospheneEngineTests/Tests/PhospheneEngine/<root>
        return url.appendingPathComponent("PhospheneEngine/Tests/Fixtures/tempo/pyramid_song.m4a").path
    }

    // MARK: - Real MIR feature stream (production FFT → MIR, 60 fps)

    private func mirFeatureStream(_ samples: [Float], sampleRate: Float) throws -> [FeatureVector] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw E.setup }
        let fft = try FFTProcessor(device: device)
        let mir = MIRPipeline()
        let hopSize = Int(sampleRate / Self.simFPS)
        var out: [FeatureVector] = []
        var offset = 0
        var time: Float = 0
        let dt = 1.0 / Self.simFPS
        while offset + 1024 <= samples.count {
            let frame = Array(samples[offset..<offset + 1024])
            _ = fft.process(samples: frame, sampleRate: sampleRate)
            var mags = [Float](repeating: 0, count: 512)
            for i in 0..<512 { mags[i] = fft.magnitudeBuffer[i] }
            out.append(mir.process(magnitudes: mags, fps: Self.simFPS, time: time, deltaTime: dt))
            offset += hopSize
            time += dt
        }
        return out
    }

    // MARK: - Real family series (best-effort; empty if PANNs is unavailable in this environment)

    private func familyStream(_ audioPath: String, seconds: Double) -> [InstrumentFamilyActivity] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let samples = try? decodeMono(audioPath, sampleRate: 44_100, seconds: seconds),
              let analyzer = try? InstrumentFamilyAnalyzer(device: device) else { return [] }
        return analyzer.analyzeFamilyActivity(samples: samples, sampleRate: 44_100)
    }

    // MARK: - ffmpeg decode / encode

    private func decodeMono(_ path: String, sampleRate: Int, seconds: Double) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ffmpeg", "-loglevel", "error", "-i", path, "-t", String(seconds),
                          "-ac", "1", "-ar", String(sampleRate), "-f", "f32le", "-"]
        let outPipe = Pipe(); proc.standardOutput = outPipe; proc.standardError = Pipe()
        try proc.run()
        let raw = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw E.decode }
        let n = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.bindMemory(to: Float.self).baseAddress, count: n)) }
    }

    private func encodeMP4(frameDir: URL, fps: Int, out: URL) throws {
        try? FileManager.default.removeItem(at: out)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ffmpeg", "-loglevel", "error", "-framerate", String(fps),
                          "-i", frameDir.appendingPathComponent("f%05d.png").path,
                          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out.path]
        proc.standardError = Pipe()
        try proc.run(); proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw E.encode }
    }

    // MARK: - PNG + dirs (BGRA→RGBA)

    private func target(_ ctx: MetalContext) throws -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.outW, height: Self.outH, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.render }
        return tex
    }

    private func makeOutputDir() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/ricercar_fluid_diag")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeBGRAToPNG(_ bgra: [UInt8], w: Int, h: Int, url: URL) throws {
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw E.render }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw E.render }
    }
}
