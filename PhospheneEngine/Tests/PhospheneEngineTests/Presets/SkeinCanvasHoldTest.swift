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
    }

    @Test("Skein.json declares passes: [\"direct\", \"mv_warp\"] and decay 1.0")
    func test_json_declaresCanvasHoldConfig() throws {
        let data = try Data(contentsOf: Self.shaderURL("Skein.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["passes"] as? [String]) == ["direct", "mv_warp"],
                "Skein.json must declare passes: [\"direct\", \"mv_warp\"] (sibling of Dragon Bloom).")
        let decay = (json?["decay"] as? NSNumber)?.doubleValue
        #expect(decay == 1.0,
                "Skein.json decay must be 1.0 (no decay) to match mvWarpPerFrame.")
    }

    // MARK: - Lossless hold (the load-bearing gate)

    @Test("Canvas-hold: a stamped mark is Hamming-0 across ≥120 frames via the live dispatch path")
    func test_canvasHold_losslessPersistence() throws {
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
        let ctx = try MetalContext()
        let device = ctx.device
        let queue = ctx.commandQueue

        // Feedback textures match the format the warp/scene pipelines were compiled
        // for (feedbackFormat → ctx.pixelFormat for Skein), or the encoder gets an
        // attachment-format mismatch and the GPU stalls (the D-137 pitfall).
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.width, height: Self.height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc)
        else { throw SkeinHoldError.textureFailed }
        try clearTextures([warpTex, composeTex, blitTex], context: ctx)

        // Zeroed audio buffers — ENGINE.1 has no audio routing; skein_fragment is
        // feature-invariant, the warp is identity regardless of features.
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride),
              let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size)
        else { throw SkeinHoldError.bufferFailed }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                             count: MemoryLayout<StemFeatures>.size)
        var features = FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)

        // Reference = frame-0 canvas (painted by the real preset fragment). Every hold
        // frame must reproduce it byte-for-byte. Patches sample flat interior regions
        // (away from the disc's AA edge) so the gate isolates decay/drift, not sub-texel
        // edge antialiasing: the stamped mark interior + an unpainted (cream) corner.
        var reference: [UInt8] = []
        var markRef: [UInt8] = []
        var openRef: [UInt8] = []
        var markDrift = 0, openDrift = 0
        var worstWholeFrameHamming = 0
        var firstDriftFrame = -1

        for frameIdx in 0..<Self.holdFrames {
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }

            if frameIdx == 0 {
                // ── Scene: paint the canvas ONCE via the preset's own fragment. ──
                try encodeScene(cmd: cmd, preset: preset, target: composeTex,
                                features: &features, fft: fft, wav: wav, stem: stem)
            } else {
                // ── Warp: identity-hold the previous canvas (warpTex → composeTex). ──
                // chromatic = 0 ⇒ no hue-zoom resample + no R→G→B transfer; the preset's
                // mvWarpPerFrame returns decay = 1.0 ⇒ decayMul = in.decay = 1.0 (no decay).
                try encodeWarp(cmd: cmd, mvWarp: mvWarp,
                               warpTex: warpTex, composeTex: composeTex, features: &features)
            }
            // ── Blit (display-only, identity post) — faithful to the live present pass. ──
            try encodeBlit(cmd: cmd, mvWarp: mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0))   // invert0 echo0 gamma1 beat0 = identity
            cmd.commit()
            cmd.waitUntilCompleted()

            let canvas = readTexture(composeTex)
            let markPatch = regionBytes(canvas, cx: Self.width / 2, cy: Self.height / 2, half: 6)  // disc interior
            let openPatch = regionBytes(canvas, cx: 20, cy: 20, half: 6)                           // unpainted cream
            if frameIdx == 0 {
                reference = canvas
                markRef = markPatch
                openRef = openPatch
                #expect(!markRef.allSatisfy { $0 == 0 },
                        "Reference mark patch is empty/black — skein_fragment did not paint the test stamp.")
            } else {
                if markPatch != markRef { markDrift += 1 }
                if openPatch != openRef { openDrift += 1 }
                let whole = hammingBytes(canvas, reference)
                if whole > worstWholeFrameHamming { worstWholeFrameHamming = whole }
                if whole != 0 && firstDriftFrame < 0 { firstDriftFrame = frameIdx }
            }

            swap(&warpTex, &composeTex)
        }

        print("""
        [skein_canvas_hold] \(Self.holdFrames - 1) hold frames at \(Self.width)×\(Self.height):
          mark-patch drift frames   = \(markDrift) (must be 0 — lossless hold at the stamp)
          unpainted-patch drift     = \(openDrift) (must be 0 — lossless hold everywhere)
          worst whole-frame Hamming = \(worstWholeFrameHamming) bytes\
          \(firstDriftFrame >= 0 ? " (first at frame \(firstDriftFrame))" : "")
          mark centre byte (BGRA)   = \(centreByte(reference))
        """)

        #expect(markDrift == 0,
                "Stamped mark drifted on \(markDrift) hold frame(s) — identity hold is not lossless.")
        #expect(openDrift == 0,
                "Unpainted texel drifted on \(openDrift) hold frame(s) — the copy is not lossless everywhere.")
        // Whole-frame Hamming 0 is the strongest form (no drift ANYWHERE, including the
        // disc's AA edge). Reported above; asserted here. If a future sampler/format
        // change introduces sub-texel edge blend, this catches it while the patch gates
        // above still localise it to flat vs edge regions.
        #expect(worstWholeFrameHamming == 0,
                """
                Canvas drifted by up to \(worstWholeFrameHamming) bytes across the hold \
                (first at frame \(firstDriftFrame)) — identity warp is resampling/decaying \
                somewhere. Expected byte-for-byte persistence.
                """)
    }

    // MARK: - Pass encoders (mirror the live mv_warp dispatch path)

    private func encodeScene(
        cmd: MTLCommandBuffer, preset: PresetLoader.LoadedPreset, target: MTLTexture,
        features: inout FeatureVector, fft: MTLBuffer, wav: MTLBuffer, stem: MTLBuffer
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture, features: inout FeatureVector
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
        var chromatic: Float = 0   // canvas-hold: identity (no hue-zoom resample, no R→G→B transfer)
        enc.setFragmentBytes(&chromatic, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31×23 quads
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

    private func clearTextures(_ texs: [MTLTexture], context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
        for tex in texs {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = tex
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
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

    /// Bytes of a (2·half+1)² patch centred at (cx, cy), row-major BGRA.
    private func regionBytes(_ px: [UInt8], cx: Int, cy: Int, half: Int) -> [UInt8] {
        var out: [UInt8] = []
        for y in (cy - half)...(cy + half) {
            for x in (cx - half)...(cx + half) {
                let idx = (y * Self.width + x) * 4
                out.append(contentsOf: px[idx..<idx + 4])
            }
        }
        return out
    }

    /// Count of differing bytes between two equal-length frames.
    private func hammingBytes(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) }
        var diff = 0
        for i in 0..<a.count where a[i] != b[i] { diff += 1 }
        return diff
    }

    private func centreByte(_ px: [UInt8]) -> String {
        let idx = ((Self.height / 2) * Self.width + Self.width / 2) * 4
        return "(\(px[idx]), \(px[idx + 1]), \(px[idx + 2]), \(px[idx + 3]))"
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
