// StaveLookSpike — CHR.2's throwaway motion-gated look spike.
//
// Answers one question with rendered frames and then gets discarded or lifted into CHR.3:
// do two band-driven traces read as two VOICES, and does stem-driven colour carry
// instrument identity? Nothing here is registered — no `.metal` in `Sources/Presets/Shaders`
// (PresetLoader enumerates `.metal`, not `.json`, so a production shader file WOULD have
// made this a 29th preset), no sidecar, no golden. The MSL is compiled from source at
// runtime; it lifts verbatim into a real `.metal` if Matt says go.
//
// Driver, settled by Matt 2026-08-13 and NOT to be second-guessed here:
//   trace POSITION  <- 6-band split, EMA-centred   (rhythm subBass+lowBass,
//                                                   melodic midHigh+highMid+high)  ~0.3 s
//   trace COLOUR    <- per-stem, drums+bass vs vocals+other                         ~2.5 s
//
// Env-gated, like every other replay harness here:
//   STAVE_SESSION=/path/to/session_dir STAVE_TRACK="Bleed" STAVE_OUT=/tmp/stave \
//   STAVE_COLOUR=0|1 swift test --package-path PhospheneEngine --filter StaveLookSpike

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared

// MARK: - Band EMA

/// One band's running-average pivot, mirroring `BandDeviationTracker` exactly (D-146):
/// seed-from-first-non-zero, two-speed warmup, `(v - ema) * 2`. Absolute thresholds on
/// AGC-normalised band values are FA #31; every position driver here is EMA-centred.
struct StaveBandEMA {
    static let decay: Float = 0.9989
    static let warmupDecay: Float = 0.9
    static let warmupFrames = 180
    static let valueCeiling: Float = 2.0

    private var avg: Float = 0
    private var warmup = 0

    mutating func rel(_ raw: Float) -> Float {
        let value = min(max(raw, 0), Self.valueCeiling)
        if value > 0 && warmup < Self.warmupFrames { warmup += 1 }
        let decay = warmup < Self.warmupFrames ? Self.warmupDecay : Self.decay
        if avg == 0 && value > 0 { avg = value }
        avg = avg * decay + value * (1 - decay)
        return (value - avg) * 2.0
    }
}

// MARK: - Vertex + config (mirrors the MSL structs; field ORDER is the contract)

struct StaveVertex {
    var posX: Float = 0, posY: Float = 0
    var colR: Float = 1, colG: Float = 1, colB: Float = 1, colA: Float = 1
    var width: Float = 0.004
}

struct StaveCfg {
    var aspect: Float = 16.0 / 9.0
}

// MARK: - StaveTrace

/// The CPU model: two history rings plotting the band split, plus the beat gridline times.
/// This is the whole spike — a trace is a time series and `FeatureVector` is instantaneous,
/// so the ring lives here exactly as `WitchlightStroke` keeps its bead trail (STAVE_PLAN §0).
/// No engine surface touched, no `SpectralHistoryBuffer` change.
final class StaveTrace: ParticleGeometry, @unchecked Sendable {

    /// Seconds of history on screen. CHR.1 measured its decorrelation in 8 s windows;
    /// the trace shows the same window so the measured numbers describe what is drawn.
    static let window: Float = 8.0

    /// Fixed per-trace gains, NOT a per-track normaliser. Chosen so the corpus-median p95
    /// excursion lands at ~0.35 NDC: measured p95|R| ≈ 0.65, p95|M| ≈ 0.094 across 15 tracks.
    /// Deliberately fixed — the gate asks whether ONE gain survives the ~4x excursion span
    /// between Bleed and Dance Yrself Clean, and an adaptive gain would hide the answer.
    static let rhythmGain: Float = 0.35 / 0.65
    static let melodicGain: Float = 0.35 / 0.094

    struct Sample {
        var audioTime: Float
        var rhythm: Float
        var melodic: Float
        /// drums+bass energyRel and vocals+other energyRel at this sample, for the
        /// colour half of the gate. Carried even in the flat-colour control so the two
        /// renders differ ONLY in the shader's use of them.
        var rhythmStem: Float
        var melodicStem: Float
    }

    private(set) var samples: [Sample] = []
    /// Audio times of beat-phase wraps — the gridlines. Plain verticals, no weighting.
    private(set) var beatTimes: [Float] = []

    private var subBassEMA = StaveBandEMA(), lowBassEMA = StaveBandEMA()
    private var midHighEMA = StaveBandEMA(), highMidEMA = StaveBandEMA(), highEMA = StaveBandEMA()
    private var lastBeatPhase: Float = 0
    private var audioTime: Float = 0

    /// True once the coloured pass is wanted. The flat control and the coloured render are
    /// the SAME geometry — only this flag differs, which is what makes the pair a control.
    let colourFromStems: Bool

    var activeParticleFraction: Float = 1.0

    private let device: MTLDevice
    private var traceBuffer: MTLBuffer
    private var gridBuffer: MTLBuffer
    private let ribbonPipeline: MTLRenderPipelineState
    private var cfg = StaveCfg()
    private var uploadedA = 0, uploadedB = 0, uploadedGrid = 0

    private static let capacity = 4096

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, colourFromStems: Bool) throws {
        self.device = device
        self.colourFromStems = colourFromStems
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        guard let vertexFunction = library.makeFunction(name: "stave_ribbon_vertex"),
              let fragmentFunction = library.makeFunction(name: "stave_ribbon_fragment") else {
            throw StaveSpikeError.functionNotFound
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        guard let attachment = descriptor.colorAttachments[0] else { throw StaveSpikeError.functionNotFound }
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        // NOT additive. The first render used `.one` here and every frame blew out to a
        // white wedge: ~480 near-collinear ribbon quads overlap heavily, and additive
        // accumulation saturates long before the trace is legible. A signal plot is a
        // line, not an emissive accumulation.
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .zero
        attachment.destinationAlphaBlendFactor = .one
        self.ribbonPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let stride = MemoryLayout<StaveVertex>.stride
        guard let tb = device.makeBuffer(length: Self.capacity * 2 * stride, options: .storageModeShared),
              let gb = device.makeBuffer(length: 256 * 2 * stride, options: .storageModeShared) else {
            throw StaveSpikeError.bufferAllocationFailed
        }
        self.traceBuffer = tb
        self.gridBuffer = gb
    }

    // MARK: ParticleGeometry

    func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advance(features: features, stems: stemFeatures)
        upload(aspect: features.aspectRatio > 0.05 ? features.aspectRatio : 16.0 / 9.0)
    }

    /// Pure-CPU tick, split out so it is drivable without a command buffer.
    func advance(features: FeatureVector, stems: StemFeatures) {
        // The RENDER clock, not `accumulatedAudioTime`. The latter is energy-weighted by
        // definition (ARCHITECTURE.md §1276), so it advances at a music-dependent rate —
        // ~12x slower than wall-clock here. That makes it an animation phase, not a clock,
        // and a time-series plot needs a uniform axis or the whole window is warped.
        audioTime = features.time

        // POSITION — the settled driver. Each band EMA-centred separately, then summed,
        // so a loud band cannot drag its partner's pivot (FA #31).
        let rhythm = subBassEMA.rel(features.subBass) + lowBassEMA.rel(features.lowBass)
        let melodic = midHighEMA.rel(features.midHigh) + highMidEMA.rel(features.highMid)
            + highEMA.rel(features.high)

        // COLOUR source — per-stem, the ~2.5 s-late channel. Pairs match the CHR.1
        // grouping that survived measurement: drums~bass and vocals~other.
        let rhythmStem = (stems.drumsEnergyRel + stems.bassEnergyRel) * 0.5
        let melodicStem = (stems.vocalsEnergyRel + stems.otherEnergyRel) * 0.5

        // Plot at ~20 Hz, not per render frame. The analyser behind these bands updates at
        // roughly 10 Hz, so a 60 Hz plot draws two duplicate points for every real one:
        // ~480 near-identical samples across the window, whose segment-to-segment direction
        // is numerical noise rather than signal. Decimating first is what makes the ribbon
        // direction meaningful at all.
        if samples.last.map({ audioTime - $0.audioTime >= 0.05 }) ?? true {
            samples.append(Sample(audioTime: audioTime, rhythm: rhythm, melodic: melodic,
                                  rhythmStem: rhythmStem, melodicStem: melodicStem))
        }

        // Beat gridlines from the beat-phase wrap. `beatsPerBar` is NOT stable within a
        // track (CHR.1 amendment §5), so every beat gets an identical plain vertical —
        // no downbeat weighting, which would need a bar length this capture cannot supply.
        if features.beatPhase01 < lastBeatPhase - 0.3 { beatTimes.append(audioTime) }
        lastBeatPhase = features.beatPhase01

        let cutoff = audioTime - Self.window
        samples.removeAll { $0.audioTime < cutoff }
        beatTimes.removeAll { $0 < cutoff }
    }

    func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        encoder.setRenderPipelineState(ribbonPipeline)
        var config = cfg
        if uploadedGrid >= 2 {
            encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&config, length: MemoryLayout<StaveCfg>.stride, index: 1)
            // One quad per gridline; the pairs are laid out [bottom, top] per line.
            for line in 0..<(uploadedGrid / 2) {
                encoder.setVertexBufferOffset(line * 2 * MemoryLayout<StaveVertex>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            }
        }
        let stride = MemoryLayout<StaveVertex>.stride
        if uploadedA >= 2 {
            encoder.setVertexBuffer(traceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&config, length: MemoryLayout<StaveCfg>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: uploadedA - 1)
        }
        if uploadedB >= 2 {
            encoder.setVertexBuffer(traceBuffer, offset: Self.capacity * stride, index: 0)
            encoder.setVertexBytes(&config, length: MemoryLayout<StaveCfg>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: uploadedB - 1)
        }
    }

    // MARK: Upload

    /// Hue for a stem-pair level. Rhythm runs warm (amber), melodic runs cool (cyan);
    /// saturation and brightness ride the pair's own deviation, so a loud drum fill
    /// should visibly heat the rhythm trace if the colour route is legible at all.
    private func colour(base: SIMD3<Float>, level: Float) -> SIMD3<Float> {
        guard colourFromStems else { return SIMD3(1, 1, 1) }   // flat-colour control
        let drive = min(max(level * 1.6 + 0.35, 0.12), 1.0)
        return SIMD3(base.x * drive, base.y * drive, base.z * drive)
    }

    func upload(aspect: Float) {
        cfg.aspect = aspect
        let pointer = traceBuffer.contents().bindMemory(to: StaveVertex.self, capacity: Self.capacity * 2)
        let window = Self.window
        let newest = audioTime
        let ordered = samples.suffix(Self.capacity)
        let count = ordered.count

        // Weight — the other half of what the stem route is asked to carry. A trace with
        // an active instrument group thickens; a dormant one thins to a hairline.
        func weight(_ level: Float) -> Float {
            guard colourFromStems else { return 0.0035 }
            return 0.0022 + min(max(level, 0), 1.2) * 0.0075
        }

        for (i, sample) in ordered.enumerated() {
            // Newest sample at the right edge, oldest at the left. The trace scrolls.
            let x = ((sample.audioTime - (newest - window)) / window) * 2.0 - 1.0
            let rhythmColour = colour(base: SIMD3(1.0, 0.62, 0.20), level: sample.rhythmStem)
            let melodicColour = colour(base: SIMD3(0.32, 0.80, 1.0), level: sample.melodicStem)
            pointer[i] = StaveVertex(
                posX: x, posY: sample.rhythm * Self.rhythmGain,
                colR: rhythmColour.x, colG: rhythmColour.y, colB: rhythmColour.z, colA: 1,
                width: weight(sample.rhythmStem))
            pointer[Self.capacity + i] = StaveVertex(
                posX: x, posY: sample.melodic * Self.melodicGain,
                colR: melodicColour.x, colG: melodicColour.y, colB: melodicColour.z, colA: 1,
                width: weight(sample.melodicStem))
        }
        uploadedA = count
        uploadedB = count

        let gridPointer = gridBuffer.contents().bindMemory(to: StaveVertex.self, capacity: 512)
        var written = 0
        for time in beatTimes.suffix(256) {
            let x = ((time - (newest - window)) / window) * 2.0 - 1.0
            // Dim, so the grid rules the field without competing with the traces.
            gridPointer[written] = StaveVertex(posX: x, posY: -0.92,
                                               colR: 0.16, colG: 0.19, colB: 0.28, colA: 1, width: 0.0016)
            gridPointer[written + 1] = StaveVertex(posX: x, posY: 0.92,
                                                   colR: 0.16, colG: 0.19, colB: 0.28, colA: 1, width: 0.0016)
            written += 2
        }
        uploadedGrid = written
    }

    // MARK: MSL

    /// Segment-quad expansion: `.lineStrip` cannot carry a per-sample thickness, and weight
    /// is half of what the stem route is being asked to deliver (gate half 2 / option B).
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // PACKED. A plain `float4 color` is 16-byte aligned in MSL, which pads this struct to a
    // 48-byte stride against Swift's 28 — the vertex buffer is then read at the wrong offsets
    // and the traces render as large mis-coloured triangles (magenta/yellow in a flat-WHITE
    // control was the tell). Packed matches the Swift layout exactly, and is the same reason
    // `Particles.metal` uses `packed_float4`.
    struct StaveVertex { packed_float2 pos; packed_float4 color; float width; };
    struct StaveCfg { float aspect; };
    struct VOut { float4 position [[position]]; float4 color; };

    vertex VOut stave_ribbon_vertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    const device StaveVertex *verts [[buffer(0)]],
                                    constant StaveCfg &cfg [[buffer(1)]]) {
        StaveVertex a = verts[iid];
        StaveVertex b = verts[iid + 1];
        // 28-byte stride, matching MemoryLayout<StaveVertex>.stride on the Swift side.
        static_assert(sizeof(StaveVertex) == 28, "StaveVertex must stay 28 bytes");
        // Perpendicular in aspect-corrected space, so the ribbon keeps an even
        // thickness on a steep segment instead of pinching.
        float2 d = float2((b.pos.x - a.pos.x) * cfg.aspect, b.pos.y - a.pos.y);
        float len = length(d);
        // A degenerate segment has no meaningful direction, so its perpendicular is pure
        // numerical noise and the quad splays in a random direction. Fall back to a
        // vertical normal rather than normalising near-zero.
        float2 n = (len > 1e-4) ? float2(-d.y, d.x) / len : float2(0.0, 1.0);
        n.x /= cfg.aspect;
        bool atEnd = (vid >= 2);
        StaveVertex s = atEnd ? b : a;
        float side = (vid & 1) ? 1.0 : -1.0;
        VOut o;
        o.position = float4(s.pos + n * side * s.width, 0.0, 1.0);
        o.color = s.color;
        return o;
    }

    fragment float4 stave_ribbon_fragment(VOut in [[stage_in]]) {
        return in.color;
    }
    """
}

enum StaveSpikeError: Error { case functionNotFound, bufferAllocationFailed }

// MARK: - Replay

/// One `features.csv` + `stems.csv` frame, carrying ONLY the fields this spike drives from.
/// Written out explicitly rather than reusing `SessionReplayHarness`: that harness is
/// ray-march-only and does not map `midHigh` / `highMid` / `high` at all, so replaying the
/// melodic trace through it would have fed it ZERO and the trace would have read as dead —
/// the exact instrument failure recorded against Faraday.
struct StaveReplayFrame {
    var features = FeatureVector(time: 0, deltaTime: 1.0 / 60.0, accumulatedAudioTime: 0)
    var stems = StemFeatures.zero
    var track = ""
}

enum StaveReplay {

    static func load(session: URL, aspect: Float) -> [StaveReplayFrame] {
        guard let featureText = try? String(contentsOf: session.appendingPathComponent("features.csv"),
                                            encoding: .utf8),
              let stemText = try? String(contentsOf: session.appendingPathComponent("stems.csv"),
                                         encoding: .utf8) else { return [] }
        let bounds = trackBounds(session.appendingPathComponent("session.log"))
        let featureLines = featureText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        let stemLines = stemText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let featureHeader = featureLines.first, let stemHeader = stemLines.first else { return [] }
        let featureIndex = columnIndex(featureHeader)
        let stemIndex = columnIndex(stemHeader)

        var out: [StaveReplayFrame] = []
        out.reserveCapacity(featureLines.count)
        for (featureLine, stemLine) in zip(featureLines.dropFirst(), stemLines.dropFirst()) {
            let ff = featureLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let sf = stemLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard ff.count > 20, sf.count > 20 else { continue }
            func f(_ name: String) -> Float { value(ff, featureIndex, name) }
            func s(_ name: String) -> Float { value(sf, stemIndex, name) }

            var frame = StaveReplayFrame()
            frame.features = FeatureVector(time: f("time"), deltaTime: f("deltaTime"),
                                           accumulatedAudioTime: f("accumulatedAudioTime"))
            frame.features.bass = f("bass"); frame.features.mid = f("mid"); frame.features.treble = f("treble")
            frame.features.subBass = f("subBass"); frame.features.lowBass = f("lowBass")
            frame.features.midHigh = f("midHigh"); frame.features.highMid = f("highMid")
            frame.features.high = f("high")
            frame.features.beatPhase01 = f("beatPhase01")
            frame.features.aspectRatio = aspect
            frame.stems.drumsEnergyRel = s("drumsEnergyRel"); frame.stems.bassEnergyRel = s("bassEnergyRel")
            frame.stems.vocalsEnergyRel = s("vocalsEnergyRel"); frame.stems.otherEnergyRel = s("otherEnergyRel")
            frame.track = track(at: f("wallclock_s"), bounds)
            out.append(frame)
        }
        return out
    }

    private static func columnIndex(_ header: Substring) -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, name) in header.split(separator: ",").map(String.init).enumerated() { index[name] = i }
        return index
    }

    private static func value(_ fields: [String], _ index: [String: Int], _ name: String) -> Float {
        guard let i = index[name], i < fields.count else { return 0 }
        return Float(fields[i]) ?? 0
    }

    /// Track boundaries, so a per-track verdict is a per-track render. `wallclock_s` is
    /// CFAbsoluteTime; the log stamps ISO-8601 UTC.
    private static func trackBounds(_ log: URL) -> [(Float, String)] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var out: [(Float, String)] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.contains("trackChangeCallback FIRED"),
                  let close = line.firstIndex(of: "]"),
                  let start = line.range(of: "current='"),
                  let end = line.range(of: "' currentArtist=") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            guard let date = formatter.date(from: stamp) else { continue }
            out.append((Float(date.timeIntervalSinceReferenceDate), String(line[start.upperBound..<end.lowerBound])))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private static func track(at wallclock: Float, _ bounds: [(Float, String)]) -> String {
        var name = ""
        for (time, title) in bounds where time <= wallclock { name = title }
        return name
    }
}

// MARK: - Suite

@Suite("StaveLookSpike")
@MainActor
struct StaveLookSpike {

    @Test("CHR.2 — render two band-driven traces from a recorded session (STAVE_SESSION=…)")
    func test_renderSpike() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sessionPath = env["STAVE_SESSION"] else {
            print("[stave] STAVE_SESSION not set — skipping")
            return
        }
        let width = Int(env["STAVE_W"] ?? "") ?? 1067
        let height = Int(env["STAVE_H"] ?? "") ?? 750
        let colour = env["STAVE_COLOUR"] == "1"
        let wanted = env["STAVE_TRACK"] ?? ""
        let outDir = URL(fileURLWithPath: env["STAVE_OUT"] ?? NSTemporaryDirectory().appending("stave"))
        let stride = Int(env["STAVE_STRIDE"] ?? "") ?? 2
        let count = Int(env["STAVE_COUNT"] ?? "") ?? 240
        let warmup = Int(env["STAVE_WARMUP"] ?? "") ?? 900

        let aspect = Float(width) / Float(height)
        let frames = StaveReplay.load(session: URL(fileURLWithPath: sessionPath), aspect: aspect)
        guard !frames.isEmpty else {
            Issue.record("no frames parsed from \(sessionPath)")
            return
        }
        let selected = wanted.isEmpty ? frames : frames.filter { $0.track.hasPrefix(wanted) }
        guard selected.count > warmup else {
            Issue.record("track '\(wanted)': \(selected.count) frames, need > \(warmup)")
            return
        }
        print("[stave] \(selected.count) frames for '\(wanted.isEmpty ? "<all>" : wanted)'"
              + "  colour=\(colour) → \(outDir.path)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let ctx = try MetalContext()
        let trace = try StaveTrace(device: ctx.device, pixelFormat: ctx.pixelFormat, colourFromStems: colour)
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        var written = 0
        for (i, frame) in selected.enumerated() {
            trace.advance(features: frame.features, stems: frame.stems)
            // Warm the EMAs and fill the 8 s window before capturing, and thereafter
            // capture every `stride`-th frame so the sequence covers real musical time.
            guard i >= warmup, (i - warmup) % stride == 0, written < count else { continue }

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            // D-037: silence renders the dark field and its grid, never black-on-black.
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.012, green: 0.014, blue: 0.022, alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { continue }
            trace.upload(aspect: aspect)
            trace.render(encoder: enc, features: frame.features)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else {
                print("[stave] frame \(written) GPU failure: \(String(describing: cmd.error))")
                continue
            }
            let pixels = HarnessTemplateCore.readBGRA(texture, width: width, height: height)
            try Self.writePNG(bgra: pixels, width: width, height: height,
                              to: outDir.appendingPathComponent(String(format: "stave_seq_%04d.png", written)))
            written += 1
        }
        print("[stave] wrote \(written) frames to \(outDir.path)")
    }

    private static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: info.rawValue) else { return nil }
            return context.makeImage()
        }
        guard let cgImage = image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        _ = CGImageDestinationFinalize(dest)
    }
}
