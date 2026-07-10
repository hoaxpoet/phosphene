// RicercarFluidVideoHarness — RICERCAR-FL: the closest-to-real validation of the Fantasia drive.
//
// Matt's bar (2026-07-08): "the most important thing is how the visuals appear in RESPONSE to musical
// signals." A static contact sheet cannot show that. This harness runs a REAL track through the
// PRODUCTION analysis path (FFTProcessor → MIRPipeline for the zero-lag band/beat features;
// InstrumentFamilyAnalyzer for the family capture, StemFeatures 48–55), drives RicercarFlowGeometry
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
    static let simW = 960, simH = 540      // trail (sim) resolution — matches the output, no upscale blur
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
        let geo = try RicercarFlowGeometry(
            device: ctx.device, library: lib.library,
            configuration: RicercarFlowConfiguration(width: Self.simW, height: Self.simH),
            pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx)
        let dir = try makeOutputDir()
        let frameDir = dir.appendingPathComponent("frames")
        try? FileManager.default.removeItem(at: frameDir)
        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

        let hop = InstrumentFamilyAnalyzer.hopSeconds
        var captured = 0
        // Sync instrumentation (per captured frame): the audio drive vs what the render did, so
        // "is it synced?" is a number, not an opinion. energy = total band deviation; balance =
        // treb−bass (a left/right position cue); coverage + centroidX = how much dye + where it is.
        var audioEnergy: [Double] = [], audioBalance: [Double] = []
        var visCoverage: [Double] = [], visCentroidX: [Double] = [], visCentroidY: [Double] = []
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
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.017, blue: 0.04, alpha: 1)
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
                let (cov, cx, cy) = coverageAndCentroid(px)
                audioEnergy.append(Double(max(0, fv.bassDev) + max(0, fv.midDev) + max(0, fv.trebDev)))
                audioBalance.append(Double(fv.trebDev - fv.bassDev))
                visCoverage.append(cov); visCentroidX.append(cx); visCentroidY.append(cy)
                captured += 1
            }
        }
        print("[ricercar_video] wrote \(captured) frames")
        reportSync(energy: audioEnergy, balance: audioBalance, coverage: visCoverage,
                   centroidX: visCentroidX, centroidY: visCentroidY)

        // 4. Encode MP4 (yuv420p for QuickTime).
        let stem = URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent
        let mp4 = dir.appendingPathComponent("ricercar_response_\(stem).mp4")
        try encodeMP4(frameDir: frameDir, fps: Self.videoFPS, out: mp4)
        print("[ricercar_video] MP4 → \(mp4.path)")
        #expect(captured > 0)
        #expect(FileManager.default.fileExists(atPath: mp4.path), "ffmpeg did not produce the MP4")
    }

    /// FANTASIA-FUGUE PROTOTYPE (RICERCAR_ECHO=1): drive `RicercarEchoGeometry` with the same real MIR stream
    /// and render an MP4 + frames, so Matt and I can judge whether a clear gesture that ANSWERS ITSELF reads as
    /// a fugue and stays locked to the music. Onsets spawn subjects; echoes answer (transformed); density
    /// scales with energy. Uncoupled from the app — this test is the only driver.
    @Test("Fugue-echo prototype: gestures answer themselves, driven by real audio → MP4")
    func test_echoPrototypeVideo() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_ECHO"] == "1" else {
            print("RicercarFluidVideoHarness: RICERCAR_ECHO not set — skipping echo prototype"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let audioPath = env["RICERCAR_AUDIO"] ?? Self.defaultFixture()
        let seconds = Double(env["RICERCAR_SECONDS"] ?? "18") ?? 18
        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("RicercarFluidVideoHarness: audio not found at \(audioPath) — skipping"); return
        }
        let mirSamples = try decodeMono(audioPath, sampleRate: 48_000, seconds: seconds)
        let features = try mirFeatureStream(mirSamples, sampleRate: 48_000)
        print("[ricercar_echo] MIR: \(features.count) frames from \(URL(fileURLWithPath: audioPath).lastPathComponent)")

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try RicercarEchoGeometry(
            device: ctx.device, library: lib.library,
            configuration: RicercarEchoConfiguration(width: Self.simW, height: Self.simH),
            pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx)
        let dir = try makeOutputDir()
        let frameDir = dir.appendingPathComponent("echo_frames")
        try? FileManager.default.removeItem(at: frameDir)
        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

        // Real instrument-family series (PANNs) → each spark's colour is the section actually playing.
        // Alive on orchestral (Beethoven), ~dead on rock (the geometry falls back to a rotating hue then).
        let familySeries = familyStream(audioPath, seconds: seconds)
        let hop = InstrumentFamilyAnalyzer.hopSeconds
        print("[ricercar_echo] family: \(familySeries.count) windows (empty = PANNs unavailable → colour falls back)")

        var captured = 0
        var audioEnergy: [Double] = [], visCoverage: [Double] = []
        for (i, fv) in features.enumerated() {
            var stem = StemFeatures.zero
            if !familySeries.isEmpty {
                let fam = InstrumentFamilyActivity.sample(
                    familySeries, atPlaybackSeconds: Double(i) / Double(Self.simFPS), hopSeconds: hop)
                let sm = fam.smoothedSIMD4, dv = fam.devSIMD4
                stem.stringsActivity = sm.x; stem.brassActivity = sm.y
                stem.woodwindsActivity = sm.z; stem.percussionActivity = sm.w
                stem.stringsActivityDev = dv.x; stem.brassActivityDev = dv.y
                stem.woodwindsActivityDev = dv.z; stem.percussionActivityDev = dv.w
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
            geo.update(features: fv, stemFeatures: stem, commandBuffer: cmd)
            let capture = (i % 2 == 0)
            if capture {
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = tex
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.017, blue: 0.04, alpha: 1)
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
                try writeBGRAToPNG(px, w: Self.outW, h: Self.outH,
                                   url: frameDir.appendingPathComponent(String(format: "f%05d.png", captured)))
                audioEnergy.append(Double(max(0, fv.bassDev) + max(0, fv.midDev) + max(0, fv.trebDev)))
                visCoverage.append(coverageAndCentroid(px).0)
                captured += 1
            }
        }
        let intensity = bestLag(audio: audioEnergy, vis: visCoverage, maxLag: 18)
        print("[ricercar_echo] wrote \(captured) frames; INTENSITY coverage vs energy r=\(String(format: "%+.2f", intensity.r)) at lag \(intensity.lag)f")
        let stem = URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent
        let mp4 = dir.appendingPathComponent("ricercar_echo_\(stem).mp4")
        try encodeMP4(frameDir: frameDir, fps: Self.videoFPS, out: mp4)
        print("[ricercar_echo] MP4 (silent) → \(mp4.path)")
        // Also mux the source audio so the visuals can be judged WITH the music (Matt: "tough to judge
        // without the music"). Best-effort — a silent MP4 already exists if this fails.
        let withMusic = dir.appendingPathComponent("ricercar_echo_\(stem)_with_music.mp4")
        if muxAudio(video: mp4, audio: audioPath, seconds: seconds, out: withMusic) {
            print("[ricercar_echo] MP4 (with music) → \(withMusic.path)")
        }
        #expect(captured > 0)
    }

    /// FAST sync/density diagnostic (RICERCAR_ECHO_DIAG=1) — drives the echo geometry over the real MIR stream
    /// with NO rendering (no PNG/ffmpeg), and reports marks/second per window + how well mark-density tracks the
    /// audio energy. Lets the onset detector be tuned in seconds instead of 2-minute video renders.
    @Test("Fugue-echo sync/density diagnostic (fast, no render)")
    func test_echoSyncDiagnostic() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RICERCAR_ECHO_DIAG"] == "1" else {
            print("RicercarFluidVideoHarness: RICERCAR_ECHO_DIAG not set — skipping"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let audioPath = env["RICERCAR_AUDIO"] ?? Self.defaultFixture()
        let seconds = Double(env["RICERCAR_SECONDS"] ?? "60") ?? 60
        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("RicercarFluidVideoHarness: audio not found — skipping"); return
        }
        let features = try mirFeatureStream(decodeMono(audioPath, sampleRate: 48_000, seconds: seconds), sampleRate: 48_000)
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try RicercarEchoGeometry(device: ctx.device, library: lib.library,
                                           configuration: RicercarEchoConfiguration(width: 320, height: 180),
                                           pixelFormat: nil)
        var energyPerSec: [Double] = Array(repeating: 0, count: Int(seconds) + 1)
        for (i, fv) in features.enumerated() {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
            geo.update(features: fv, stemFeatures: StemFeatures.zero, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
            let sec = Int(Double(i) / Double(Self.simFPS))
            if sec < energyPerSec.count {
                energyPerSec[sec] += Double(max(0, fv.bass) + max(0, fv.mid) + max(0, fv.treble))
            }
        }
        // marks per second
        var marksPerSec = Array(repeating: 0, count: Int(seconds) + 1)
        for t in geo.spawnTimes { let sec = Int(t); if sec < marksPerSec.count { marksPerSec[sec] += 1 } }
        let secs = marksPerSec.count
        let mAvg = Double(geo.totalSpawns) / seconds
        let emptySecs = marksPerSec.prefix(Int(seconds)).filter { $0 == 0 }.count
        // correlation of marks/sec vs energy/sec (density-sync proxy)
        let r = pearson(energyPerSec, marksPerSec.map { Double($0) })
        let kc = geo.spawnKindCounts
        print("[echo_diag] \(geo.totalSpawns) marks over \(Int(seconds))s = \(String(format: "%.1f", mAvg))/s; " +
              "empty seconds: \(emptySecs)/\(Int(seconds)); density↔energy r=\(String(format: "%+.2f", r))")
        print("[echo_diag] articulation split — legato:\(kc[0]) staccato:\(kc[1]) pizz:\(kc[2])")
        print("[echo_diag] marks/sec: " + marksPerSec.prefix(secs).map(String.init).joined(separator: " "))
        #expect(geo.totalSpawns > 0)
    }

    /// Mux the source audio onto a silent rendered MP4 (first `seconds`). Returns false on any ffmpeg failure.
    private func muxAudio(video: URL, audio: String, seconds: Double, out: URL) -> Bool {
        try? FileManager.default.removeItem(at: out)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ffmpeg", "-loglevel", "error", "-i", video.path, "-i", audio,
                          "-map", "0:v", "-map", "1:a", "-t", String(seconds),
                          "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out.path]
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return false }
        return proc.terminationStatus == 0
    }

    /// Repo-relative fixture resolved from this file's path (…/PhospheneEngine/Tests/PhospheneEngineTests/
    /// Diagnostics/ → up 4 → repo root), so the default works regardless of the test's working directory.
    private static func defaultFixture(file: String = #filePath) -> String {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // Diagnostics/PhospheneEngineTests/Tests/PhospheneEngine/<root>
        return url.appendingPathComponent("PhospheneEngine/Tests/Fixtures/tempo/pyramid_song.m4a").path
    }

    // MARK: - Sync determination (audio ↔ visual correlation + lag)

    /// Lit-pixel fraction + the mean (x, y) of the lit pixels (0…1) — how much light, and where. A pixel
    /// is "lit" when its luminance rises above the deep ground (sRGB luminance ≈ 42 for the ground; 70 is
    /// a clean margin), so the metric measures the glowing light-trail, not the whole frame.
    private func coverageAndCentroid(_ px: [UInt8]) -> (Double, Double, Double) {
        var n = 0, sumX = 0.0, sumY = 0.0
        let count = px.count / 4
        for i in 0..<count {
            let b = Double(px[i * 4]), g = Double(px[i * 4 + 1]), r = Double(px[i * 4 + 2])
            if 0.299 * r + 0.587 * g + 0.114 * b > 70 {
                n += 1
                sumX += Double(i % Self.outW) / Double(Self.outW)
                sumY += Double(i / Self.outW) / Double(Self.outH)
            }
        }
        let cov = Double(n) / Double(count)
        return (cov, n > 0 ? sumX / Double(n) : 0.5, n > 0 ? sumY / Double(n) : 0.5)
    }

    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count); guard n > 2 else { return 0 }
        let ma = a.prefix(n).reduce(0, +) / Double(n), mb = b.prefix(n).reduce(0, +) / Double(n)
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<n { let x = a[i] - ma, y = b[i] - mb; num += x * y; da += x * x; db += y * y }
        return (da > 0 && db > 0) ? num / (da * db).squareRoot() : 0
    }

    /// Best correlation of `vis` against `audio` over integer lags (vis delayed by `lag` frames).
    private func bestLag(audio: [Double], vis: [Double], maxLag: Int) -> (r: Double, lag: Int) {
        var best = (r: -2.0, lag: 0)
        for lag in -maxLag...maxLag {
            var a: [Double] = [], v: [Double] = []
            for i in 0..<vis.count where i - lag >= 0 && i - lag < audio.count {
                a.append(audio[i - lag]); v.append(vis[i])
            }
            let r = pearson(a, v)
            if r > best.r { best = (r, lag) }
        }
        return best
    }

    private func std(_ a: [Double]) -> Double {
        let m = a.reduce(0, +) / Double(max(1, a.count))
        return (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(max(1, a.count))).squareRoot()
    }

    private func reportSync(energy: [Double], balance: [Double], coverage: [Double],
                            centroidX: [Double], centroidY: [Double]) {
        // INTENSITY (the key flow-field metric): does the AMOUNT of glowing light track the music's
        // energy, and at what lag? A strong r near lag 0 = the flow surges WITH the music (motion sync).
        let intensity = bestLag(audio: energy, vis: coverage, maxLag: 18)
        // VERTICAL: the mean height of the light vs energy — a weaker cue for a flow field (families sit
        // in loose bands), reported for completeness. σ shows how much the light's centre moves.
        let vertical = bestLag(audio: energy, vis: centroidY.map { -$0 }, maxLag: 18)
        print("""
        [ricercar_sync] ── audio↔visual determination (\(coverage.count) frames @ \(Self.videoFPS) fps) ──
          INTENSITY: coverage vs energy  r=\(String(format: "%+.2f", intensity.r)) at lag \(intensity.lag)f (\(intensity.lag * 1000 / Self.videoFPS) ms)
          VERTICAL : centroidY vs energy r=\(String(format: "%+.2f", vertical.r)) at lag \(vertical.lag)f (\(vertical.lag * 1000 / Self.videoFPS) ms), σ=\(String(format: "%.3f", std(centroidY)))
          READ: strong VERTICAL r near lag 0 with σ≳0.03 = the visual MOVES with the music (B is working);
                σ≈0 = static. balance σ (x)=\(String(format: "%.3f", std(centroidX)))
        """)
    }

    // MARK: - Real MIR feature stream (production FFT → MIR, 60 fps)

    private func mirFeatureStream(_ samples: [Float], sampleRate: Float) throws -> [FeatureVector] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw E.setup }
        let fft = try FFTProcessor(device: device)
        let mir = MIRPipeline()
        // FL.11 beat-sync demo: install a fixed-BPM BeatGrid so `beatPhase01`/`pulseAmp01` populate and the
        // rendered light PULSES on the grid beat (set RICERCAR_BPM=143.2 for the session's Beethoven).
        // CAVEAT: a fixed grid has the right CADENCE but not the real onset-calibrated PHASE — the live
        // app's cached grid (±~20 ms lock) is what aligns the pulse to the actual downbeats. Off by default.
        if let bpmStr = ProcessInfo.processInfo.environment["RICERCAR_BPM"], let bpm = Double(bpmStr), bpm > 0 {
            let secs = Double(samples.count) / Double(sampleRate)
            let beatsPerBar = 4
            let period = 60.0 / bpm
            var beats: [Double] = [], downbeats: [Double] = []
            var i = 0
            while Double(i) * period < secs + period {
                let tb = Double(i) * period
                beats.append(tb)
                if i % beatsPerBar == 0 { downbeats.append(tb) }
                i += 1
            }
            mir.setBeatGrid(BeatGrid(beats: beats, downbeats: downbeats, bpm: bpm,
                                     beatsPerBar: beatsPerBar, barConfidence: 1,
                                     frameRate: Double(Self.simFPS), frameCount: beats.count))
            print("[ricercar_video] installed fixed BeatGrid bpm=\(bpm) beats=\(beats.count) (beat-sync demo)")
        }
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
