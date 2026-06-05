// SkeinCanvasHoldTest — Skein.ENGINE.1 canvas-hold persistence gate.
//
// Proves the LOSSLESS canvas-hold property: under identity warp + no decay +
// no R→G→B transfer, a stamped mark is carried forward BYTE-FOR-BYTE by the
// mv_warp warp pass, frame after frame, with no decay / drift / resampling error.
//
// Production-pipeline parity (CLAUDE.md "Test in the production-grade rendering
// pipeline. No shortcuts." + FA #66): this test exercises the SAME live dispatch
// path the app uses for an mv_warp preset — scene (the preset's own
// `skein_fragment`, frame 0) → warp pass (the production-compiled `warpState`,
// frames 1+) → blit → swap, in a loop — NOT `preset.pipelineState` in isolation.
// The warp pass is the new machinery ENGINE.1 introduces; this drives it for
// ≥120 hold frames and asserts the canvas never changes.
//
// What this proves (structural): identity-hold is lossless — Hamming 0 at the
// stamped mark AND at an unpainted texel across ≥120 frames.
// What this does NOT prove (Skein.1+): mark morphology, audio coupling, wetness,
// palette — none of which exist yet.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Skein canvas-hold persistence")
struct SkeinCanvasHoldTest {

    private static let width  = 256
    private static let height = 256
    // Frame 0 paints the canvas via skein_fragment; frames 1...holdFrames-1 hold it
    // via the warp pass. 131 frames ⇒ 130 hold frames, comfortably past the ≥120 bar.
    private static let holdFrames = 131

    // MARK: - Static-source guards (cheap regression sentries)

    @Test("Skein.metal declares the canvas-hold mv_warp + fragment functions")
    func test_metalSource_declaresCanvasHoldFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Skein.metal"), encoding: .utf8)
        #expect(src.contains("fragment float4 skein_fragment("),
                "Skein.metal missing skein_fragment entry point.")
        #expect(src.contains("MVWarpPerFrame mvWarpPerFrame("),
                "Skein.metal missing mvWarpPerFrame (D-027 canvas-hold contract).")
        #expect(src.contains("float2 mvWarpPerVertex("),
                "Skein.metal missing mvWarpPerVertex (D-027 canvas-hold contract).")
        // Identity + no-decay are the canvas-hold invariants — guard the literals.
        #expect(src.contains("return uv;"),
                "Skein.metal mvWarpPerVertex must be identity (return uv) for canvas-hold.")
        #expect(src.contains("pf.decay = 1.0"),
                "Skein.metal mvWarpPerFrame must set decay = 1.0 (no decay) for canvas-hold.")
        // Skein.ENGINE.1.1 (D-143): the test stamp moved to the marks-on-top overlay.
        #expect(src.contains("vertex SkeinGeoVertexOut skein_geometry_vertex("),
                "Skein.metal missing skein_geometry_vertex (marks-on-top overlay, D-143).")
        #expect(src.contains("fragment float4 skein_geometry_fragment("),
                "Skein.metal missing skein_geometry_fragment (marks-on-top overlay, D-143).")
    }

    @Test("Skein.json declares canvas-hold config + a marks-on-top block (D-143)")
    func test_json_declaresCanvasHoldConfig() throws {
        let data = try Data(contentsOf: Self.shaderURL("Skein.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["passes"] as? [String]) == ["direct", "mv_warp"],
                "Skein.json must declare passes: [\"direct\", \"mv_warp\"] (sibling of Dragon Bloom).")
        let decay = (json?["decay"] as? NSNumber)?.doubleValue
        #expect(decay == 1.0,
                "Skein.json decay must be 1.0 (no decay) to match mvWarpPerFrame.")
        // Skein.ENGINE.1.1 (D-143): the marks-on-top block drives chromatic / comp / draw
        // params + the per-preset canvas-clear ground per-preset (no longer hard-coded to
        // Dragon Bloom). Skein needs chromatic=0 (lossless, non-cycling), no beat pump, and
        // a cream ground.
        let marks = json?["marks"] as? [String: Any]
        #expect(marks != nil, "Skein.json must declare a `marks` block (marks-on-top config, D-143).")
        #expect((marks?["chromatic"] as? NSNumber)?.doubleValue == 0.0,
                "Skein.json marks.chromatic must be 0 (lossless, non-cycling canvas-hold).")
        #expect((marks?["beat_pulse"] as? Bool) == false,
                "Skein.json marks.beat_pulse must be false (a quiet held canvas — no audio until Skein.4).")
        let clear = marks?["canvas_clear"] as? [NSNumber]
        #expect(clear?.count == 3,
                "Skein.json marks.canvas_clear must be an RGB triple (the held cream ground).")
    }

    // MARK: - Marks-on-top lossless hold (the load-bearing ENGINE.1.1 gate)

    @Test("Marks-on-top: disc lands on the cream ground, chromatic=0 holds Hamming-0 (chromatic=1.0 cycles) — live dispatch path")
    func test_marksOnTop_creamGroundDiscHoldsLossless() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("SkeinCanvasHoldTest: no Metal device — skipping")
            return
        }
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Skein"
        }) else {
            Issue.record("Skein preset not loaded — bundle resource not copied?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines else {
            Issue.record("Skein preset.mvWarpPipelines is nil — JSON passes array misconfigured.")
            return
        }
        // The per-preset scene-geometry overlay (skein_geometry_*) must have compiled via
        // the D-143 per-prefix lookup — this is the mechanism that draws the marks on top.
        guard let overlay = mvWarp.sceneGeometryState else {
            Issue.record("Skein mvWarpPipelines.sceneGeometryState is nil — skein_geometry_* not resolved (D-143 per-prefix lookup).")
            return
        }
        // The held GROUND comes from the per-preset canvas clear (Pass 0 is skipped on the
        // marks-on-top path). Source the cream from the descriptor — the same value the
        // live app feeds setupMVWarp.
        guard let creamRGB = preset.descriptor.marks?.canvasClear else {
            Issue.record("Skein descriptor has no marks.canvas_clear — the held cream ground is unplumbed (D-143).")
            return
        }
        let cream = MTLClearColor(
            red: Double(creamRGB.x), green: Double(creamRGB.y), blue: Double(creamRGB.z), alpha: 1)
        let ctx = try MetalContext()

        // chromatic = 0 (Skein's config): the held canvas must persist byte-for-byte.
        let hold = try runMarksOnTopHold(chromatic: 0, cream: cream, overlay: overlay, mvWarp: mvWarp, ctx: ctx)
        // chromatic = 1.0 (Dragon-Bloom-style control): the shared warp's R→G→B transfer
        // must make the held canvas DRIFT — proving chromatic=0 is what gives the lossless,
        // non-cycling hold (the load-bearing distinguisher between Skein and Dragon Bloom).
        let cycle = try runMarksOnTopHold(chromatic: 1.0, cream: cream, overlay: overlay, mvWarp: mvWarp, ctx: ctx)

        print("""
        [skein_marks_on_top] \(Self.holdFrames - 1) hold frames at \(Self.width)×\(Self.height):
          ground corner (BGRA)      = \(hold.groundCorner)  (cream — must NOT be black)
          disc centre (BGRA)        = \(hold.discCentre)    (teal — the overlay landed)
          chromatic=0 worst Hamming = \(hold.worstHamming)  (must be 0 — lossless hold)
          chromatic=1 worst Hamming = \(cycle.worstHamming) (must be > 0 — colour cycling)
        """)

        // 1. The disc LANDS via the overlay on a CREAM ground. The ENGINE.1.1 bug being
        //    fixed is "marks-on-top ⇒ black canvas / no cream ground" (Pass 0 skipped, the
        //    clear was hard-coded black). The ground must be cream, the disc must be teal.
        #expect(!isBlack(hold.groundCorner),
                "Ground corner is black — the per-preset cream canvas clear did not take (marks-on-top renders on black). \(hold.groundCorner)")
        #expect(isCreamish(hold.groundCorner),
                "Ground corner is not cream-ish (bright, R≳G≳B) — clear colour wrong. \(hold.groundCorner)")
        #expect(hold.discCentre != hold.groundCorner,
                "Disc centre equals the ground — the marks-on-top overlay did not draw the stamp.")
        #expect(isTealish(hold.discCentre),
                "Disc centre is not the teal stamp colour (B≳G > R) — overlay output/blend wrong. \(hold.discCentre)")

        // 2. chromatic = 0 ⇒ Hamming-0 hold — the ENGINE.1 persistence property preserved,
        //    now with the stamp REDRAWN each frame via the overlay (consecutive frames byte-
        //    identical).
        #expect(hold.worstHamming == 0,
                "Canvas drifted by up to \(hold.worstHamming) bytes at chromatic=0 — the marks-on-top hold is not lossless.")

        // 3. chromatic = 1.0 ⇒ the canvas colour-cycles (drift > 0). Without this the
        //    chromatic transfer would be inert and chromatic=0 would prove nothing.
        #expect(cycle.worstHamming > 0,
                "Control run at chromatic=1.0 did NOT cycle — the chromatic transfer is inert, so chromatic=0 is not a meaningful distinguisher.")
    }

    // MARK: - Marks-on-top dispatch driver (mirrors drawWithMVWarp's strandsOnTop branch)

    private struct MarksHoldResult {
        var groundCorner: [UInt8]
        var discCentre: [UInt8]
        var worstHamming: Int
    }

    /// Drive the live marks-on-top dispatch path for `holdFrames` frames at the given
    /// `chromatic`: clear warp+compose to the cream ground once, then each frame
    /// warp(prev) → overlay(disc on top) → blit → read → swap. Mirrors `drawWithMVWarp`'s
    /// `strandsOnTop` branch (Pass 0 skipped; the ground is the clear; the disc is the
    /// `skein_geometry_*` overlay composited normal-alpha onto the held frame).
    private func runMarksOnTopHold(
        chromatic: Float,
        cream: MTLClearColor,
        overlay: MTLRenderPipelineState,
        mvWarp: PresetLoader.MVWarpCompiledPipelines,
        ctx: MetalContext
    ) throws -> MarksHoldResult {
        let device = ctx.device, queue = ctx.commandQueue
        // Feedback textures match the format the warp/overlay pipelines were compiled for
        // (feedbackFormat → ctx.pixelFormat for Skein), or the encoder gets an attachment-
        // format mismatch and the GPU stalls (the D-137 pitfall).
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.width, height: Self.height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc)
        else { throw SkeinHoldError.textureFailed }
        // The held ground IS the canvas clear (cream), not black — this is the D-143 fix.
        try clearTextures([warpTex, composeTex], to: cream, context: ctx)
        try clearTextures([blitTex], to: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1), context: ctx)

        var features = FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)
        var reference: [UInt8] = [], groundCorner: [UInt8] = [], discCentre: [UInt8] = []
        var worst = 0

        for frameIdx in 0..<Self.holdFrames {
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
            // Pass 1: identity warp holds the previous canvas (warpTex → composeTex). At
            // chromatic=0 + decay=1.0 this is a lossless copy; at chromatic=1.0 the R→G→B
            // transfer + hue-zoom resample make it drift.
            try encodeWarp(cmd: cmd, mvWarp: mvWarp, warpTex: warpTex, composeTex: composeTex,
                           features: &features, chromatic: chromatic)
            // Pass 2: marks-on-top — draw the disc normal-alpha onto the held canvas.
            try encodeOverlay(cmd: cmd, overlay: overlay, target: composeTex, features: &features)
            // Pass 3: blit (display-only, identity post) — faithful to the live present pass.
            try encodeBlit(cmd: cmd, mvWarp: mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0))   // invert0 echo0 gamma1 beat0 = identity
            cmd.commit()
            cmd.waitUntilCompleted()

            let canvas = readTexture(composeTex)
            if frameIdx == 0 {
                reference = canvas
                groundCorner = pixelAt(canvas, x: 20, y: 20)                       // unpainted ground
                discCentre = pixelAt(canvas, x: Self.width / 2, y: Self.height / 2) // disc interior
            } else {
                worst = max(worst, hammingBytes(canvas, reference))
            }
            swap(&warpTex, &composeTex)
        }
        return MarksHoldResult(groundCorner: groundCorner, discCentre: discCentre, worstHamming: worst)
    }

    // MARK: - Pass encoders (mirror the live mv_warp dispatch path)

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture, features: inout FeatureVector, chromatic: Float
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .clear   // the 32×24 grid covers every pixel; clear is moot
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.warpState)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stems = StemFeatures.zero
        enc.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = SceneUniforms()
        enc.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        enc.setFragmentTexture(warpTex, index: 0)
        var chromaticCopy = chromatic
        enc.setFragmentBytes(&chromaticCopy, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31×23 quads
        enc.endEncoding()
    }

    /// Pass 2 of the marks-on-top path: draw the overlay (Skein's disc) normal-alpha onto
    /// the held/warped canvas. `loadAction = .load` preserves the warped ground (only the
    /// disc texels are blended in), exactly as `encodeMVWarpScenePass`'s strandsOnTop branch.
    private func encodeOverlay(
        cmd: MTLCommandBuffer, overlay: MTLRenderPipelineState, target: MTLTexture,
        features: inout FeatureVector
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load     // keep the held ground; blend the disc on top
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(overlay)
        // drawSceneGeometryOverlay binds features@0 + stems@1; skein_geometry_vertex ignores
        // them (the disc is static at ENGINE.1.1), but bind them for live-path parity.
        enc.setVertexBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stems = StemFeatures.zero
        enc.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        enc.endEncoding()
    }

    private func encodeBlit(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        src: MTLTexture, dst: MTLTexture, post: SIMD4<Float>
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = dst
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.blitState)
        enc.setFragmentTexture(src, index: 0)
        var post = post
        enc.setFragmentBytes(&post, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    // MARK: - Helpers

    private func clearTextures(_ texs: [MTLTexture], to clearColor: MTLClearColor, context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
        for tex in texs {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = tex
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = clearColor
            desc.colorAttachments[0].storeAction = .store
            if let enc = cmd.makeRenderCommandEncoder(descriptor: desc) { enc.endEncoding() }
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    private func readTexture(_ tex: MTLTexture) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        tex.getBytes(&px, bytesPerRow: Self.width * 4,
                     from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)
        return px
    }

    /// The 4 BGRA bytes at pixel (x, y).
    private func pixelAt(_ px: [UInt8], x: Int, y: Int) -> [UInt8] {
        let idx = (y * Self.width + x) * 4
        return Array(px[idx..<idx + 4])
    }

    /// Count of differing bytes between two equal-length frames.
    private func hammingBytes(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) }
        var diff = 0
        for i in 0..<a.count where a[i] != b[i] { diff += 1 }
        return diff
    }

    // BGRA byte order. "Black" = all channels near 0; "cream" = bright with R≳G≳B (warm);
    // "teal" = the stamp (B≳G clearly above R). Generous thresholds — these distinguish the
    // ground/disc/black, not exact colours (sRGB-encode rounding is fine).
    private func isBlack(_ p: [UInt8]) -> Bool { p[0] < 12 && p[1] < 12 && p[2] < 12 }
    private func isCreamish(_ p: [UInt8]) -> Bool {
        let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
        return r > 140 && g > 120 && b > 100 && r >= g && g >= b   // warm, bright
    }
    private func isTealish(_ p: [UInt8]) -> Bool {
        let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
        return b > r + 30 && g > r + 30   // deep teal: blue/green well above red
    }

    private static func shaderURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // /Presets/
            .deletingLastPathComponent()   // /PhospheneEngineTests/
            .deletingLastPathComponent()   // /Tests/
            .deletingLastPathComponent()   // /PhospheneEngine/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders/\(name)")
    }
}

private enum SkeinHoldError: Error {
    case textureFailed
    case bufferFailed
    case cmdBufferFailed
    case encoderFailed
}
