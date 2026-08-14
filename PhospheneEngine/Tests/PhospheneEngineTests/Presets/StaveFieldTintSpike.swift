// StaveFieldTintSpike — CHR.3 task 1. The D4 gate, and the whole point of opening with it.
//
// D-216 moved the ENTIRE stem story off the traces and onto a field tint. STAVE_DESIGN §7
// rates that mechanism at grounding level **3 — no empirical grounding**: "a 3.0 s lag is
// invisible on a slow surface" is an argument, and nothing had rendered it. This spike
// renders the tint ALONE — no traces, no grid, no sparkle — and answers one question:
//
//   can a viewer see the field change when the stem balance changes,
//   at 3.0 s latency and diffuse?
//
// If no, D-216 option A (drop stems entirely) becomes live again and that is Matt's
// re-scope, not a tuning round.
//
// ⚠ THE DRIVE IS NOT `energyRel`. Measured this increment, before rendering:
// `energyRel = (energy - runningAvg) * 2` with a PER-STEM ~10 s EMA (StemAnalyzer), so a
// sustained drum-led section drives its own deviation back toward zero and the balance
// self-cancels on exactly the timescale a field tint lives at. Between-vs-within variance
// of the 3 s-smoothed drive over 20 s sections, seven captures:
//
//     drive                         eta^2         Cohen's d (extreme sections)
//     REL   (deviation difference)  0.11 - 0.20   1.46 - 2.12
//     RATIO (raw energy share)      0.26 - 0.56   1.77 - 3.98
//
// RATIO wins on every capture. It is a SHARE — scale-invariant, so an AGC gain change
// cancels top and bottom — which is why it is not the FA #31 failure (an absolute
// threshold on an AGC-normalised value). Clean-chain local captures score higher still
// (eta^2 0.64-0.76, d 3.1-5.0).
//
//   STAVE_TINT_SESSION=/path/to/session_dir STAVE_TINT_OUT=/tmp/stave_tint \
//   STAVE_TINT_TAU=3.0 swift test --package-path PhospheneEngine --filter StaveFieldTintSpike

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared

// MARK: - The drive

/// The field tint's drive: the `drums+bass` share of total stem energy, smoothed onto the
/// slow surface a tint lives on. Split out from the renderer so the gate can measure the
/// same numbers it draws.
struct StaveFieldTint {

    /// Corpus-measured mapping window. Section means across seven captures span
    /// 0.447-0.526 and centre near 0.485, so a FIXED window covers the corpus and no
    /// per-track normaliser is needed. `tanh` rather than a clamp so an out-of-window
    /// track compresses instead of pinning to an end stop.
    static let centre: Float = 0.485
    static let scale: Float = 0.035

    /// Seconds. The field's own slowness, on top of the ~3.0 s the stem pipeline already
    /// carries. Deliberately separate: the lag is the pipeline's, the smoothing is ours.
    let tau: Float

    init(tau: Float = 3.0) { self.tau = tau }

    private var share: Float = -1
    private var lastTime: Float = -1

    /// Raw share in [0,1]; 0.5 is a perfectly even split between the two stem pairs.
    private(set) var rawShare: Float = 0.5

    /// Smoothed tint parameter in [0,1]. 0 = vocals/other lead (cool), 1 = drums/bass lead (warm).
    private(set) var tint: Float = 0.5

    mutating func advance(stems: StemFeatures, time: Float) {
        let rhythm = stems.drumsEnergy + stems.bassEnergy
        let melodic = stems.vocalsEnergy + stems.otherEnergy
        let total = rhythm + melodic
        rawShare = total > 1e-9 ? rhythm / total : 0.5

        if share < 0 || lastTime < 0 {
            share = rawShare
        } else {
            let dt = max(0, time - lastTime)
            share += (rawShare - share) * (1 - exp(-dt / max(tau, 1e-3)))
        }
        lastTime = time
        tint = 0.5 + 0.5 * tanh((share - Self.centre) / Self.scale)
    }
}

// MARK: - Renderer

/// Fullscreen field pass: tint + haze + cloud texture, no traces, no grid, no sparkle.
/// Deliberately the whole field and nothing else — a gate that renders the traces too
/// cannot say whether the TINT is what the viewer read.
final class StaveFieldPass {

    private let pipeline: MTLRenderPipelineState
    private var uniforms = Uniforms()

    struct Uniforms {
        var tint: Float = 0.5
        var time: Float = 0
        var aspect: Float = 16.0 / 9.0
        var pad: Float = 0
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        let library = try device.makeLibrary(source: Self.source, options: nil)
        guard let vertexFunction = library.makeFunction(name: "stave_field_vertex"),
              let fragmentFunction = library.makeFunction(name: "stave_field_fragment") else {
            throw StaveSpikeError.functionNotFound
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0]?.pixelFormat = pixelFormat
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func render(encoder: MTLRenderCommandEncoder, tint: Float, time: Float, aspect: Float) {
        uniforms = Uniforms(tint: tint, time: time, aspect: aspect, pad: 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float tint; float time; float aspect; float pad; };
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut stave_field_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid & 1) ? 1.0 : -1.0, (vid >> 1) ? 1.0 : -1.0);
        VOut o;
        o.position = float4(p, 0.0, 1.0);
        o.uv = p * 0.5 + 0.5;
        return o;
    }

    static float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    static float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
                   mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
    }

    /// Four octaves, per the SHADER_CRAFT quality floor.
    static float fbm(float2 p) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < 4; ++i) { v += a * noise(p); p *= 2.03; a *= 0.5; }
        return v;
    }

    fragment float4 stave_field_fragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;

        // Reference 03_palette_field_hue_drift: the FIELD carries the colour. Cool
        // teal/violet when vocals+other lead, warm amber/orange when drums+bass lead.
        float3 cool = float3(0.13, 0.42, 0.55);
        float3 warm = float3(0.72, 0.36, 0.13);
        float3 tintColour = mix(cool, warm, u.tint);

        // Reference 01_macro: a HORIZON. Hazy atmosphere in the upper half, traces would
        // inhabit a band across the lower-middle, near-black beneath.
        float haze = smoothstep(-0.15, 0.95, uv.y);
        haze *= haze;

        // Slow cloud texture so the tint reads as a ROOM rather than a flat wash. Drifts
        // on the render clock only — no audio route (L5: no autonomous MOTION means no
        // trace motion; the atmosphere's slow drift is the source's own character).
        float cloud = fbm(float2(uv.x * 3.0 * u.aspect, uv.y * 2.2) + float2(u.time * 0.013, u.time * 0.004));
        cloud = 0.55 + 0.45 * cloud;

        float3 col = tintColour * haze * cloud * 0.85;

        // A faint ground glow so the lower field is not a dead plate.
        col += tintColour * 0.10 * smoothstep(0.55, 0.0, uv.y) * cloud;

        // D-037: silence renders the field, never black.
        col = max(col, float3(0.012, 0.014, 0.022));
        return float4(col, 1.0);
    }
    """
}

// MARK: - Suite

@Suite("StaveFieldTintSpike")
@MainActor
struct StaveFieldTintSpike {

    /// Frames-plus-numbers gate. Renders the tint alone across the whole capture, writes a
    /// strip sampled evenly across the track, and — the part that actually answers the
    /// question — the two 20 s sections whose tint is furthest apart, side by side.
    @Test("CHR.3 D4 — render the field tint alone (STAVE_TINT_SESSION=…)")
    func test_fieldTintAlone() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sessionPath = env["STAVE_TINT_SESSION"] else {
            print("[tint] STAVE_TINT_SESSION not set — skipping")
            return
        }
        let width = Int(env["STAVE_TINT_W"] ?? "") ?? 640
        let height = Int(env["STAVE_TINT_H"] ?? "") ?? 450
        let tau = Float(env["STAVE_TINT_TAU"] ?? "") ?? 3.0
        let strip = Int(env["STAVE_TINT_STRIP"] ?? "") ?? 16
        let outDir = URL(fileURLWithPath: env["STAVE_TINT_OUT"]
                         ?? NSTemporaryDirectory().appending("stave_tint"))

        let aspect = Float(width) / Float(height)
        let frames = StaveReplay.load(session: URL(fileURLWithPath: sessionPath), aspect: aspect)
        guard frames.count > 100 else {
            Issue.record("only \(frames.count) frames parsed from \(sessionPath)")
            return
        }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Pass 1 — the drive, on CPU, so the frames drawn and the numbers reported agree.
        var driver = StaveFieldTint(tau: tau)
        var tints: [Float] = []
        var shares: [Float] = []
        tints.reserveCapacity(frames.count)
        for frame in frames {
            driver.advance(stems: frame.stems, time: frame.features.time)
            tints.append(driver.tint)
            shares.append(driver.rawShare)
        }
        let times = frames.map(\.features.time)
        let span = (times.last ?? 0) - (times.first ?? 0)

        // 20 s sections, so "the balance changed" means a musical section changed.
        let sectionCount = max(2, Int(span / 20.0))
        var buckets = [[Int]](repeating: [], count: sectionCount)
        for (i, t) in times.enumerated() {
            let b = min(sectionCount - 1, Int((t - times[0]) / max(span, 1e-3) * Float(sectionCount)))
            buckets[b].append(i)
        }
        let sectionMeans = buckets.map { idx -> Float in
            idx.isEmpty ? 0.5 : idx.reduce(Float(0)) { $0 + tints[$1] } / Float(idx.count)
        }
        guard let hottest = sectionMeans.indices.max(by: { sectionMeans[$0] < sectionMeans[$1] }),
              let coolest = sectionMeans.indices.min(by: { sectionMeans[$0] < sectionMeans[$1] })
        else { return }

        print("[tint] \(sessionPath)")
        print("[tint] \(frames.count) frames, \(String(format: "%.0f", span)) s, tau=\(tau) s,"
              + " \(sectionCount) sections")
        print("[tint] tint per 20 s section: "
              + sectionMeans.map { String(format: "%.2f", $0) }.joined(separator: " "))
        print("[tint] raw share range p5..p95: "
              + String(format: "%.3f..%.3f", Self.pct(shares, 5), Self.pct(shares, 95)))
        print("[tint] extremes: section \(coolest) tint \(String(format: "%.2f", sectionMeans[coolest]))"
              + " (melodic-led) vs section \(hottest) tint"
              + " \(String(format: "%.2f", sectionMeans[hottest])) (rhythm-led),"
              + " gap \(String(format: "%.2f", sectionMeans[hottest] - sectionMeans[coolest]))")

        // Pass 2 — render.
        let ctx = try MetalContext()
        let field = try StaveFieldPass(device: ctx.device, pixelFormat: ctx.pixelFormat)
        let texture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height)

        func draw(_ index: Int, to url: URL) throws {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
            field.render(encoder: enc, tint: tints[index], time: times[index], aspect: aspect)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else {
                print("[tint] GPU failure: \(String(describing: cmd.error))")
                return
            }
            try Self.writePNG(bgra: HarnessTemplateCore.readBGRA(texture, width: width, height: height),
                              width: width, height: height, to: url)
        }

        // The strip — evenly across the track, so the drift is visible as a sequence.
        for s in 0..<strip {
            let index = min(frames.count - 1, s * frames.count / strip)
            try draw(index, to: outDir.appendingPathComponent(
                String(format: "strip_%02d_t%.2f.png", s, tints[index])))
        }
        // The gate frame pair — the two sections furthest apart in stem balance.
        for (label, section) in [("melodic_led", coolest), ("rhythm_led", hottest)] {
            let idx = buckets[section][buckets[section].count / 2]
            try draw(idx, to: outDir.appendingPathComponent(
                String(format: "extreme_%@_t%.2f.png", label, tints[idx])))
        }
        print("[tint] wrote \(strip + 2) frames to \(outDir.path)")

        // Contiguous sequence INSIDE one section. The extremes above prove the tint moves
        // between sections; this asks the opposite question — does it sit still enough
        // WITHIN one? eta^2 says 44-74 % of the drive's variance is within-section, and a
        // field that churns through its whole range inside a chorus is a defect even
        // though every between-section frame pair looks right.
        if let seqDir = env["STAVE_TINT_SEQ_OUT"] {
            let seq = URL(fileURLWithPath: seqDir)
            try FileManager.default.createDirectory(at: seq, withIntermediateDirectories: true)
            let sectionIdx = buckets[hottest]
            let step = max(1, sectionIdx.count / 120)
            var written = 0
            for (n, i) in sectionIdx.enumerated() where n % step == 0 && written < 120 {
                try draw(i, to: seq.appendingPathComponent(String(format: "seq_%04d.png", written)))
                written += 1
            }
            let inSection = sectionIdx.map { tints[$0] }
            let mean = inSection.reduce(0, +) / Float(inSection.count)
            let sd = (inSection.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(inSection.count)).squareRoot()
            print("[tint] within-section (\(hottest)) tint: mean \(String(format: "%.2f", mean))"
                  + " sd \(String(format: "%.3f", sd))"
                  + " range \(String(format: "%.2f..%.2f", inSection.min() ?? 0, inSection.max() ?? 0))")
            print("[tint] wrote \(written) contiguous frames to \(seq.path)")
        }
    }

    private static func pct(_ xs: [Float], _ p: Int) -> Float {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, p * (s.count - 1) / 100))]
    }

    static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
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
