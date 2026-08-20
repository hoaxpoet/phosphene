// MeshStemBindingTests — proof that a mesh preset's OBJECT stage can read StemFeatures.
//
// ★★ WHY THIS EXISTS, AND WHY IT DOES NOT USE A PRESET. This is the coverage the FTR.4 gate
// provided until FTR.33 retired it. That gate rendered Fractal Tree twice, changing only
// `other_onset_rate`, and required the pixels to differ — because binding a buffer and the GPU
// reading it are different claims and only the second one matters. Matt then moved Fractal Tree's
// tips onto the beat, which removed the preset's only stem route, and Fractal Tree is the ONLY
// mesh preset in the repo. So the gate had no consumer left and began failing by correctly
// reporting a route that was gone on purpose.
//
// Retiring it left a real hole: nothing proved `MeshGenerator`'s buffer 2/3/5 bindings reach the
// object stage, so the next mesh preset wanting a stem route would find out by shipping a dead
// one. That is the `vocalsPitchConfidence`-at-0%-for-five-months class, and it is exactly what a
// deleted-because-red gate causes.
//
// The fix is to stop gating this on whatever a preset happens to want THIS week. The claim is
// about the ENGINE, so the consumer is a five-line mesh shader compiled here at runtime that
// reads `StemFeatures` at buffer(3) and paints it. No bundle resource, no `.metal` file, and no
// preset can retire it by changing its own routing.
//
// It also pins the preamble's `StemFeatures` layout as a side effect: the shader is compiled
// against `PresetLoader.shaderPreamble`, the same string the real loader compiles, so a field
// added to the Swift struct without updating that copy fails here too.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Mesh stem binding (the engine claim, not a preset's)")
struct MeshStemBindingTests {

    /// One meshlet, one full-viewport triangle, coloured from a single `StemFeatures` field.
    ///
    /// Deliberately minimal: it asserts one thing, so a failure means the binding, never the
    /// shader's own arithmetic. `other_onset_rate` is the field the retired FTR.4 gate drove, kept
    /// so a bisect across that retirement compares like with like.
    private static let testShaderSource = """
    struct StemProbePayload { float level; };

    [[object, max_total_threads_per_threadgroup(1)]]
    void stem_probe_object(object_data StemProbePayload* payload [[payload]],
                           mesh_grid_properties mgp,
                           constant FeatureVector& f [[buffer(0)]],
                           constant StemFeatures& stems [[buffer(3)]])
    {
        // THE WHOLE POINT: the value crosses from buffer(3) into the payload on the object stage.
        payload->level = saturate(stems.other_onset_rate / 8.0f);
        mgp.set_threadgroups_per_grid(uint3(1, 1, 1));
    }

    struct StemProbeVertex { float4 position [[position]]; float level; };
    using StemProbeMesh = metal::mesh<StemProbeVertex, void, 3, 1, metal::topology::triangle>;

    [[mesh, max_total_threads_per_threadgroup(3)]]
    void stem_probe_mesh(StemProbeMesh out,
                         const object_data StemProbePayload& payload [[payload]],
                         uint tid [[thread_index_in_threadgroup]])
    {
        if (tid == 0) { out.set_primitive_count(1); }
        const float2 corners[3] = { float2(-1.0f, -3.0f), float2(-1.0f, 1.0f), float2(3.0f, 1.0f) };
        StemProbeVertex v;
        v.position = float4(corners[tid], 0.0f, 1.0f);
        v.level = payload.level;
        out.set_vertex(tid, v);
        out.set_index(tid, tid);
    }

    fragment float4 stem_probe_fragment(StemProbeVertex in [[stage_in]])
    {
        return float4(in.level, in.level, in.level, 1.0f);
    }
    """

    // MARK: - The gate

    /// A 20× change in a stem field must change the rendered pixels.
    ///
    /// If this fails, `MeshGenerator` is binding `StemFeatures` somewhere the object stage cannot
    /// see it, and **every** stem route on every future mesh preset is silently dead.
    @MainActor
    @Test("the object stage reads StemFeatures at buffer(3)")
    func objectStageReadsStemFeatures() throws {
        let ctx = try MetalContext()
        guard ctx.device.supportsFamily(.apple8) else { return }   // no native mesh pipeline

        let source = PresetLoader.shaderPreamble + "\n" + Self.testShaderSource
        let library = try ctx.device.makeLibrary(source: source, options: nil)
        let meshDesc = MTLMeshRenderPipelineDescriptor()
        meshDesc.objectFunction = library.makeFunction(name: "stem_probe_object")
        meshDesc.meshFunction = library.makeFunction(name: "stem_probe_mesh")
        meshDesc.fragmentFunction = library.makeFunction(name: "stem_probe_fragment")
        meshDesc.colorAttachments[0].pixelFormat = ctx.pixelFormat
        let (pipeline, _) = try ctx.device.makeRenderPipelineState(descriptor: meshDesc, options: [])

        let generator = MeshGenerator(
            device: ctx.device,
            pipelineState: pipeline,
            configuration: .init(maxVerticesPerMeshlet: 3, maxPrimitivesPerMeshlet: 1,
                                 meshThreadCount: 3))
        generator.renderDeltaOverride = 1.0 / 60.0

        let width = 32, height = 32
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        let target = try #require(ctx.device.makeTexture(descriptor: texDesc))

        func render(onsetRate: Float) throws -> Int {
            var stems = StemFeatures.zero
            stems.otherOnsetRate = onsetRate
            var features = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                         time: 0, deltaTime: 1.0 / 60.0)
            features.aspectRatio = Float(width) / Float(height)

            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: rpd))
            generator.draw(encoder: enc, features: features, stems: stems)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            #expect(cmd.status == .completed)

            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            target.getBytes(&pixels, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            // The shader paints the whole viewport one grey, so any pixel answers — the CENTRE
            // is read rather than a mean so a partially-covered frame cannot average into a pass.
            let centre = ((height / 2) * width + width / 2) * 4
            return Int(pixels[centre + 1])
        }

        let quiet = try render(onsetRate: 0.3)
        let busy = try render(onsetRate: 6.0)

        #expect(busy > quiet + 20, """
            other_onset_rate 0.3 → 6.0 moved the rendered value \\(quiet) → \\(busy). The object \
            stage is NOT reading StemFeatures at buffer(3): binding a buffer is not the same as \
            the GPU consuming it, and every mesh stem route depends on this. Restored at PERF.10 \
            after FTR.33 retired the Fractal-Tree-shaped version of this gate.
            """)
    }

    /// AND THE BEAT-HELD COPY AT buffer(5) IS REACHABLE TOO. `MeshGenerator` binds three stem
    /// slots — live at 3, arc at 2, beat-held at 5 — and FTR.13 added slot 5 specifically so a
    /// per-stem route could step on beats. Slot 3 working says nothing about slot 5, which is the
    /// one a future rhythm-locked stem route would want.
    @MainActor
    @Test("the object stage reads the beat-held StemFeatures at buffer(5)")
    func objectStageReadsHeldStemFeatures() throws {
        let ctx = try MetalContext()
        guard ctx.device.supportsFamily(.apple8) else { return }

        let probe = Self.testShaderSource
            .replacingOccurrences(of: "constant StemFeatures& stems [[buffer(3)]]",
                                  with: "constant StemFeatures& stems [[buffer(5)]]")
        let library = try ctx.device.makeLibrary(source: PresetLoader.shaderPreamble + "\n" + probe,
                                                options: nil)
        let meshDesc = MTLMeshRenderPipelineDescriptor()
        meshDesc.objectFunction = library.makeFunction(name: "stem_probe_object")
        meshDesc.meshFunction = library.makeFunction(name: "stem_probe_mesh")
        meshDesc.fragmentFunction = library.makeFunction(name: "stem_probe_fragment")
        meshDesc.colorAttachments[0].pixelFormat = ctx.pixelFormat
        let (pipeline, _) = try ctx.device.makeRenderPipelineState(descriptor: meshDesc, options: [])

        let generator = MeshGenerator(
            device: ctx.device, pipelineState: pipeline,
            configuration: .init(maxVerticesPerMeshlet: 3, maxPrimitivesPerMeshlet: 1,
                                 meshThreadCount: 3))
        generator.renderDeltaOverride = 1.0 / 60.0

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: 32, height: 32, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        let target = try #require(ctx.device.makeTexture(descriptor: texDesc))

        /// The HELD copy only moves once a beat has latched it, so unlike slot 3 this needs the
        /// hold advanced with a wrapping `beatPhase01` first — a single draw would compare two
        /// unlatched snapshots and read them as identical, which is how FTR.30's own wiring gate
        /// managed to measure nothing.
        func render(onsetRate: Float) throws -> Int {
            var stems = StemFeatures.zero
            stems.otherOnsetRate = onsetRate
            for step in 0..<180 {
                var warm = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                        time: Float(step) / 60.0, deltaTime: 1.0 / 60.0)
                warm.beatsPerBar = 4
                warm.beatPhase01 = Float(step % 40) / 40.0
                warm.aspectRatio = 1
                generator.advanceBeatHold(warm, stems: stems)
            }
            var features = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                        time: 3, deltaTime: 1.0 / 60.0)
            features.beatsPerBar = 4
            features.aspectRatio = 1

            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: rpd))
            generator.draw(encoder: enc, features: features, stems: stems)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()

            var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
            target.getBytes(&pixels, bytesPerRow: 32 * 4,
                            from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
            return Int(pixels[(16 * 32 + 16) * 4 + 1])
        }

        let quiet = try render(onsetRate: 0.3)
        let busy = try render(onsetRate: 6.0)
        #expect(busy > quiet + 20, """
            the beat-held stems at buffer(5) moved the rendered value only \\(quiet) → \\(busy). \
            Slot 5 is the one a beat-locked stem route reads (FTR.13); slot 3 passing does not \
            cover it.
            """)
    }
}
