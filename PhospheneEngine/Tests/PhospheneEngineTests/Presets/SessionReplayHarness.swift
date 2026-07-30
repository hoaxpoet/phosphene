// SessionReplayHarness — FLY.6: render a preset from a REAL recorded session.
//
// WHY THIS EXISTS (BUG-071 round 6). Across several rounds of Fractal Fly-By
// review (that preset since retired, D-201), Matt twice said "what you are
// seeing looks a lot nicer than what I
// was seeing." That was the actual defect: the offline checks did not reproduce
// the production renderer, so every look conclusion was drawn from a cleaner
// image than the live one. The divergences were not subtle —
//
//   * synthetic silence FeatureVectors instead of the track's real audio, so
//     nothing that keys off arousal / bass / valence behaved as it does live;
//   * `applyAudioModulation` (per-frame fog, light intensity, valence tint) was
//     never called at all — it lived on RenderPipeline, which the harness
//     bypasses (moved onto RayMarchPipeline at FLY.6 so both share one impl);
//   * a fresh pipeline per frame, which reset MetalFX to passthrough and hid the
//     entire temporal-AA path;
//   * 1920×1080 offline vs a ~1067×750 window live — half the pixels, so
//     markedly worse aliasing on screen than in any render I looked at.
//
// So: replay the session's own `features.csv`, frame by frame, through the real
// `RayMarchPipeline.render` seam, at the real viewport size. What comes out is
// what Matt saw — which is the only image worth forming an opinion about.
//
// Env-gated. Invocation:
//   REPLAY_SESSION=/path/to/session_dir \
//   REPLAY_PRESET="Volumetric Lithograph" \
//   REPLAY_OUT=/tmp/replay \
//   REPLAY_W=1067 REPLAY_H=750 \
//   REPLAY_FROM=0 REPLAY_COUNT=90 \
//   swift test --package-path PhospheneEngine --filter SessionReplay

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - SessionReplayHarness

@Suite("SessionReplay")
@MainActor
struct SessionReplayHarness {

    /// One row of a session's `features.csv`, mapped onto the fields the render
    /// path actually reads. Unlisted columns are ignored rather than guessed at.
    private struct Row {
        var time: Float = 0
        var deltaTime: Float = 1.0 / 60.0
        var bass: Float = 0, mid: Float = 0, treble: Float = 0
        var subBass: Float = 0, lowBass: Float = 0
        var beatBass: Float = 0, beatMid: Float = 0, beatComposite: Float = 0
        var spectralCentroid: Float = 0, spectralFlux: Float = 0
        var valence: Float = 0, arousal: Float = 0
        var accumulatedAudioTime: Float = 0
        var bassAttRel: Float = 0
        var beatPhase01: Float = 0
        // Grid + deviation fields. Any route the harness does not carry is silently
        // fed ZERO, and the resulting render tests nothing — the FLY.6 divergence in
        // its purest form (Faraday's subharmonic beat-lock and its transient accent
        // both read as "not working" until these were mapped).
        var barPhase01: Float = 0
        var bassDev: Float = 0
        var pulseAmp01: Float = 0
        var pulsePhase01: Float = 0
        var pulseBeatIndex: Float = 0
        var pulseRegionalBlend01: Float = 0
    }

    private static func loadRows(_ csv: URL) throws -> [Row] {
        let text = try String(contentsOf: csv, encoding: .utf8)
        // CRLF-safe split (the CENSUS harness hit \r\n graphemes before).
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let header = lines.first else { return [] }
        let cols = header.split(separator: ",").map(String.init)
        var index: [String: Int] = [:]
        for (i, c) in cols.enumerated() { index[c] = i }
        func get(_ f: [String], _ name: String) -> Float {
            guard let i = index[name], i < f.count else { return 0 }
            return Float(f[i]) ?? 0
        }
        var out: [Row] = []
        for line in lines.dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count > 4 else { continue }
            var r = Row()
            r.time = get(f, "time");               r.deltaTime = get(f, "deltaTime")
            r.bass = get(f, "bass");               r.mid = get(f, "mid")
            r.treble = get(f, "treble");           r.subBass = get(f, "subBass")
            r.lowBass = get(f, "lowBass");         r.beatBass = get(f, "beatBass")
            r.beatMid = get(f, "beatMid");         r.beatComposite = get(f, "beatComposite")
            r.spectralCentroid = get(f, "spectralCentroid")
            r.spectralFlux = get(f, "spectralFlux")
            r.valence = get(f, "valence");         r.arousal = get(f, "arousal")
            r.accumulatedAudioTime = get(f, "accumulatedAudioTime")
            r.bassAttRel = get(f, "bassAttRel");   r.beatPhase01 = get(f, "beatPhase01")
            // the session logs bar phase in PERMILLE
            r.barPhase01 = get(f, "barPhase01_permille") / 1000.0
            r.bassDev = get(f, "bassDev")
            r.pulseAmp01 = get(f, "pulse_amp01")
            r.pulsePhase01 = get(f, "pulse_phase01")
            r.pulseBeatIndex = get(f, "pulse_beat_index")
            r.pulseRegionalBlend01 = get(f, "pulse_regional_blend01")
            out.append(r)
        }
        return out
    }

    private static func feature(from r: Row, aspect: Float) -> FeatureVector {
        var f = FeatureVector(time: r.time, deltaTime: r.deltaTime,
                              accumulatedAudioTime: r.accumulatedAudioTime)
        f.bass = r.bass; f.mid = r.mid; f.treble = r.treble
        f.subBass = r.subBass; f.lowBass = r.lowBass
        f.beatBass = r.beatBass; f.beatMid = r.beatMid; f.beatComposite = r.beatComposite
        f.spectralCentroid = r.spectralCentroid; f.spectralFlux = r.spectralFlux
        f.valence = r.valence; f.arousal = r.arousal
        f.bassAttRel = r.bassAttRel; f.beatPhase01 = r.beatPhase01
        f.barPhase01 = r.barPhase01; f.bassDev = r.bassDev; f.pulseAmp01 = r.pulseAmp01
        f.pulsePhase01 = r.pulsePhase01
        f.pulseBeatIndex = r.pulseBeatIndex
        f.pulseRegionalBlend01 = r.pulseRegionalBlend01
        f.aspectRatio = aspect
        return f
    }

    /// Load the session's per-frame stem features. The harness previously passed
    /// `StemFeatures.zero`, so every stem-driven route in every ray-march preset was
    /// replayed against SILENCE — the routes could not move, and any look or coupling
    /// conclusion drawn from those frames was about an image production never makes.
    /// `stems.csv` column names match the `StemFeatures` property names exactly.
    private static func loadStems(_ csv: URL) -> [StemFeatures] {
        guard let text = try? String(contentsOf: csv, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let header = lines.first else { return [] }
        var index: [String: Int] = [:]
        for (i, c) in header.split(separator: ",").map(String.init).enumerated() { index[c] = i }
        var out: [StemFeatures] = []
        for line in lines.dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count > 4 else { continue }
            func g(_ n: String) -> Float {
                guard let i = index[n], i < f.count else { return 0 }
                return Float(f[i]) ?? 0
            }
            var s = StemFeatures.zero
            s.drumsEnergy = g("drumsEnergy");   s.bassEnergy = g("bassEnergy")
            s.vocalsEnergy = g("vocalsEnergy"); s.otherEnergy = g("otherEnergy")
            s.drumsBeat = g("drumsBeat");       s.bassBeat = g("bassBeat")
            s.vocalsBeat = g("vocalsBeat");     s.otherBeat = g("otherBeat")
            s.drumsEnergyRel = g("drumsEnergyRel");   s.drumsEnergyDev = g("drumsEnergyDev")
            s.bassEnergyRel = g("bassEnergyRel");     s.bassEnergyDev = g("bassEnergyDev")
            s.vocalsEnergyRel = g("vocalsEnergyRel"); s.vocalsEnergyDev = g("vocalsEnergyDev")
            s.otherEnergyRel = g("otherEnergyRel");   s.otherEnergyDev = g("otherEnergyDev")
            s.drumsOnsetRate = g("drumsOnsetRate");   s.drumsAttackRatio = g("drumsAttackRatio")
            s.bassOnsetRate = g("bassOnsetRate");     s.bassAttackRatio = g("bassAttackRatio")
            s.vocalsOnsetRate = g("vocalsOnsetRate"); s.vocalsAttackRatio = g("vocalsAttackRatio")
            s.otherOnsetRate = g("otherOnsetRate");   s.otherAttackRatio = g("otherAttackRatio")
            s.vocalsPitchHz = g("vocalsPitchHz")
            s.vocalsPitchConfidence = g("vocalsPitchConfidence")
            out.append(s)
        }
        return out
    }

    @Test("replay a recorded session through the real render path (REPLAY_SESSION=…)")
    func test_replaySession() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sessionPath = env["REPLAY_SESSION"] else {
            print("[replay] REPLAY_SESSION not set — skipping")
            return
        }
        let sessionDir = URL(fileURLWithPath: sessionPath)
        guard let presetName = env["REPLAY_PRESET"] else {
            print("[replay] REPLAY_PRESET not set — skipping")
            return
        }
        let outDir = URL(fileURLWithPath: env["REPLAY_OUT"] ?? NSTemporaryDirectory().appending("replay"))
        // Default to the windowed size Matt actually watches, NOT 1080p.
        let width  = Int(env["REPLAY_W"] ?? "") ?? 1067
        let height = Int(env["REPLAY_H"] ?? "") ?? 750
        let from   = Int(env["REPLAY_FROM"] ?? "") ?? 0
        let count  = Int(env["REPLAY_COUNT"] ?? "") ?? 90

        let rows = try Self.loadRows(sessionDir.appendingPathComponent("features.csv"))
        // REPLAY_ZERO_STEMS=1 reproduces the pre-HARNESS.1 behaviour (stems fed as
        // silence) so the A/B shows exactly what the broken instrument was hiding.

        let zeroStems = env["REPLAY_ZERO_STEMS"] == "1"
        let stemRows = zeroStems ? [] : Self.loadStems(sessionDir.appendingPathComponent("stems.csv"))
        if stemRows.isEmpty {
            print("[replay] WARNING: no stems.csv rows — stem-driven routes will replay against SILENCE")
        }
        guard !rows.isEmpty else {
            Issue.record("no rows parsed from \(sessionPath)/features.csv")
            return
        }
        // Playback starts where accumulatedAudioTime begins advancing — the
        // "beginning" Matt keeps reporting as worst. Everything before that is
        // pre-roll with the visual frozen.
        let firstAudio = rows.firstIndex { $0.accumulatedAudioTime > 0 } ?? 0
        let start = from > 0 ? from : firstAudio
        let slice = Array(rows[min(start, rows.count - 1)..<min(start + count, rows.count)])
        print("[replay] \(rows.count) rows; playback starts at row \(firstAudio); "
              + "replaying \(slice.count) from row \(start) at \(width)×\(height)")

        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }),
              let gbufferState = preset.rayMarchPipelineState else {
            Issue.record("preset '\(presetName)' not found or not ray-march")
            return
        }

        // SLOT-8 STATE. Some presets keep their entire coupling in a per-preset CPU
        // state buffer rather than in FeatureVector routes — Lumen Mosaic's per-cell
        // pattern lives in LumenPatternState at fragment slot 8, driven by
        // LumenPatternEngine (D-LM-buffer-slot-8). Without it the preset renders a
        // STATIC default: re-validation measured 0.00 stem sensitivity AND 0.00
        // frame-to-frame motion, i.e. the harness was rendering a dead image. This is a
        // distinct gap class from an unmapped feature field.
        let lumenEngine = presetName == "Lumen Mosaic"
            ? LumenPatternEngine(device: ctx.device)
            : nil

        // Production wiring, in production order.
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.metalFXEnabled = preset.descriptor.usesMetalFXTemporal
        pipeline.metalFXRenderScale = preset.descriptor.effectiveRenderScale
        pipeline.motionPipelineState = preset.motionPipelineState
        pipeline.allocateTextures(width: width, height: height)
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)
        let uniforms = preset.descriptor.makeSceneUniforms()
        pipeline.sceneUniforms = uniforms
        // `baseScene` is what applyAudioModulation modulates AROUND. Seeded here
        // exactly as VisualizerEngine+Presets.applyPreset does — without it the
        // modulation would key off zeros and the lighting would not match live.
        var snap = RayMarchPipeline.BaseSceneSnapshot()
        snap.cameraPosition = SIMD3(uniforms.cameraOriginAndFov.x,
                                    uniforms.cameraOriginAndFov.y,
                                    uniforms.cameraOriginAndFov.z)
        snap.lightIntensity = uniforms.lightPositionAndIntensity.w
        snap.lightColor = SIMD3(uniforms.lightColor.x, uniforms.lightColor.y, uniforms.lightColor.z)
        snap.fogFar = uniforms.sceneParamsB.y
        snap.fov = uniforms.cameraOriginAndFov.w
        pipeline.baseScene = snap
        // Seed the dolly from the sidecar exactly as applyPreset does, so a
        // dollying preset (Volumetric Lithograph) replays with its real forward
        // flight instead of a static camera (BUG-074 replay-harness parity gap).
        pipeline.cameraDollySpeed = preset.descriptor.sceneDollySpeed


        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        var postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: width, height: height)
            postChain = chain
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        let aspect = Float(width) / Float(height)
        var prevAudioTime: Float = slice.first?.accumulatedAudioTime ?? 0
        var failures = 0

        for (i, row) in slice.enumerated() {
            var features = Self.feature(from: row, aspect: aspect)

            // Exactly what RenderPipeline+RayMarch does per frame, in order.
            pipeline.sceneUniforms.lightingParams.z = prevAudioTime
            pipeline.sceneUniforms.sceneParamsA.x = row.accumulatedAudioTime
            pipeline.sceneUniforms.sceneParamsA.y = aspect
            pipeline.sceneUniforms.sceneParamsB.z = pipeline.stepCountMultiplier
            pipeline.applyAudioModulation(features: features)
            prevAudioTime = row.accumulatedAudioTime

            let stemsThisFrame = stemRows.isEmpty
                ? StemFeatures.zero
                : stemRows[min(start + i, stemRows.count - 1)]

            // Tick per-preset CPU state before the render reads it, matching the app's
            // `setMeshPresetTick` ordering.
            lumenEngine?.tick(features: features, stems: stemsThisFrame, stemsLive: true)

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &features,
                fftBuffer: buffers.fft, waveformBuffer: buffers.waveform,
                stemFeatures: stemsThisFrame,
                outputTexture: outTex,
                commandBuffer: cmd,
                noiseTextures: noise,
                iblManager: ibl,
                postProcessChain: postChain,
                presetFragmentBuffer3: lumenEngine?.patternBuffer)
            cmd.commit()
            cmd.waitUntilCompleted()
            if cmd.status != .completed {
                failures += 1
                print("[replay] frame \(i) GPU failure: \(String(describing: cmd.error))")
                continue
            }
            let px = HarnessTemplateCore.readBGRA(outTex, width: width, height: height)
            try Self.writePNG(bgra: px, width: width, height: height,
                              to: outDir.appendingPathComponent(String(format: "replay_%03d.png", i)))
        }
        print("[replay] wrote \(slice.count - failures) frames to \(outDir.path)"
              + (failures > 0 ? "  (\(failures) GPU failures)" : ""))
    }

    private static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                              | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let cg = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let c = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: cs, bitmapInfo: bi.rawValue) else { return nil }
            return c.makeImage()
        }
        guard let img = cg,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, img, nil)
        _ = CGImageDestinationFinalize(dest)
    }
}
