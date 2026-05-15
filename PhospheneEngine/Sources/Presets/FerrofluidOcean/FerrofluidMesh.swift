// FerrofluidMesh — Tessellated quad mesh + pipeline for the
// V.9 Session 4.5c Phase 1 Step B mesh-displacement path.
//
// Owns the vertex buffer (positions + UVs), the index buffer (triangle
// indices), and the G-buffer pipeline state that pairs
// `ferrofluid_mesh_vertex` with `ferrofluid_mesh_gbuffer_fragment`
// (see Renderer/Shaders/FerrofluidMesh.metal).
//
// Replaces the SDF ray-march G-buffer path for Ferrofluid Ocean only.
// The lighting pass downstream is unchanged — `raymarch_lighting_fragment`
// reads the G-buffer as before, routes to matID == 2 → Leitl four-layer
// material.

import Metal
import Shared
import os.log

private let meshLogger = Logger(subsystem: "com.phosphene.presets", category: "FerrofluidMesh")

// MARK: - FerrofluidMesh

/// Tessellated quad mesh + G-buffer pipeline for the mesh-displacement
/// rendering path. Matches Leitl's `spikes.vert.glsl` architecture
/// (vertex shader samples a heightmap and displaces vertices).
public final class FerrofluidMesh: @unchecked Sendable {

    // MARK: - Configuration

    /// Mesh resolution — vertices per side. World patch is 20 × 20 wu
    /// (see `FerrofluidParticles.worldSpan`).
    ///
    /// **Round 35 (V.9 Session 4.5c Phase 1, 2026-05-15): 256 → 512.**
    /// At 256² verts the density was 12.8 verts/wu → ~2.2 verts per
    /// spike radius at `spikeBaseRadius = 0.17` — too coarse to resolve
    /// the 5:1 cone tip; rasterizer linear-interpolation across triangle
    /// faces smeared peak silhouettes into rounded blobs and caused
    /// adjacent peaks to read as parallel ridges (Matt
    /// `2026-05-15T19-16-34Z` capture review). The height texture is
    /// already 4096² and carries crystal-clear cones; the mesh was the
    /// bottleneck on tip sharpness. 512² lifts density to 25.6 verts/wu
    /// → ~4.4 verts per spike radius / ~9 verts per spike diameter,
    /// enough to carve out each cone's tip distinctly.
    ///
    /// 513² = 263 169 vertices → UInt32 indices remain mandatory (already
    /// in use; see `idxStride` below). 511² × 2 = 522 242 triangles total.
    /// Memory: vertex buffer 5.0 MB + index buffer 6.0 MB = 11.0 MB total
    /// (+7.4 MB vs round 34). Per-frame vertex-shader cost rises ~4× but
    /// vertex stages are not the bottleneck at this preset's draw counts
    /// (M2 Pro session GPU times 2-15 ms with significant headroom);
    /// fragment cost is unchanged (same pixel coverage, smaller
    /// triangles).
    public static let segmentsPerSide: Int = 512

    /// Vertices per side = segments + 1.
    public static let verticesPerSide: Int = segmentsPerSide + 1

    /// Total vertex count. Indexed with UInt32 (see `idxStride` below) —
    /// no upper bound from the index type at any reasonable resolution.
    public static var vertexCount: Int { verticesPerSide * verticesPerSide }

    /// Triangle count = `segmentsPerSide² × 2`.
    public static var triangleCount: Int { segmentsPerSide * segmentsPerSide * 2 }

    /// Index count = `triangleCount × 3`.
    public static var indexCount: Int { triangleCount * 3 }

    /// Vertex buffer slot — chosen high to avoid colliding with the
    /// `[[buffer(0)]]` / `[[buffer(3)]]` / `[[buffer(4)]]` argument-buffer
    /// bindings the vertex shader declares for FeatureVector / StemFeatures /
    /// SceneUniforms. Metal's `stage_in` vertex-fetch path and `[[buffer(N)]]`
    /// argument-buffer path share the same binding-table slots.
    static let kVertexBufferSlot: Int = 16

    // MARK: - Mesh vertex layout
    //
    // Position (float3) + UV (float2) = 20 bytes per vertex. Matches
    // `FerrofluidMeshVertex` in FerrofluidMesh.metal. SIMD-aligned to
    // 16 by the implicit struct padding in MSL; we mirror that here.

    public struct Vertex: Equatable {
        public var positionX: Float
        public var positionY: Float
        public var positionZ: Float
        public var uvU:       Float
        public var uvV:       Float
        // 4 bytes padding (matches MSL `[[attribute]]` layout for
        // float3+float2 → 20 bytes; we'll set stride 20 in the descriptor).
        // Swift compiles this struct to 20 bytes naturally (no end-pad
        // since all members are Float-aligned).

        public init(positionX: Float, positionY: Float, positionZ: Float,
                    uvU: Float, uvV: Float) {
            self.positionX = positionX
            self.positionY = positionY
            self.positionZ = positionZ
            self.uvU = uvU
            self.uvV = uvV
        }
    }

    // MARK: - GPU resources

    public let vertexBuffer:      MTLBuffer
    public let indexBuffer:       MTLBuffer
    public let pipelineState:     MTLRenderPipelineState
    public let depthStencilState: MTLDepthStencilState

    // MARK: - Init

    /// Allocate the mesh buffers + compile the G-buffer pipeline state.
    /// Returns nil if any allocation or pipeline compilation fails.
    public init?(device: MTLDevice,
                 library: MTLLibrary,
                 colorAttachmentFormats: [MTLPixelFormat],
                 depthAttachmentFormat: MTLPixelFormat) {
        guard colorAttachmentFormats.count == 3 else {
            meshLogger.error("FerrofluidMesh: expected 3 G-buffer attachment formats; got \(colorAttachmentFormats.count)")
            return nil
        }

        // ── Allocate vertex buffer ───────────────────────────────────
        let vertexStride = MemoryLayout<Vertex>.stride
        let totalVerts   = Self.vertexCount
        let vbLen        = totalVerts * vertexStride
        guard let vb = device.makeBuffer(length: vbLen, options: .storageModeShared) else {
            meshLogger.error("FerrofluidMesh: vertex buffer allocation failed (\(vbLen) bytes)")
            return nil
        }
        self.vertexBuffer = vb

        // Populate the grid. Vertex `(col, row)` sits at world XZ
        // `worldOrigin + (col/segments, row/segments) × worldSpan` with
        // Y = 0 (the vertex shader displaces Y based on heightmap).
        // UV addresses the heightmap with the same mapping the bake uses
        // — `(col/segments, row/segments)` directly.
        let ptr = vb.contents().bindMemory(to: Vertex.self, capacity: totalVerts)
        let originX = FerrofluidParticles.worldOriginX
        let originZ = FerrofluidParticles.worldOriginZ
        let span    = FerrofluidParticles.worldSpan
        let segs    = Float(Self.segmentsPerSide)
        for row in 0 ..< Self.verticesPerSide {
            for col in 0 ..< Self.verticesPerSide {
                let normU = Float(col) / segs
                let normV = Float(row) / segs
                let worldX = originX + normU * span
                let worldZ = originZ + normV * span
                ptr[row * Self.verticesPerSide + col] = Vertex(
                    positionX: worldX, positionY: 0, positionZ: worldZ,
                    uvU: normU, uvV: normV)
            }
        }

        // ── Allocate index buffer (UInt32 — 256² vertices exceeds 65 535) ─
        let idxStride = MemoryLayout<UInt32>.stride
        let ibLen     = Self.indexCount * idxStride
        guard let ib = device.makeBuffer(length: ibLen, options: .storageModeShared) else {
            meshLogger.error("FerrofluidMesh: index buffer allocation failed (\(ibLen) bytes)")
            return nil
        }
        self.indexBuffer = ib

        // Populate triangle indices. Each grid cell (`segmentsPerSide²`
        // total) produces two triangles forming a quad — CCW winding
        // when viewed from +Y so the cross-product normal in the vertex
        // shader points "up" for the flat (undisplaced) plane.
        let idxPtr  = ib.contents().bindMemory(to: UInt32.self, capacity: Self.indexCount)
        let perRow  = UInt32(Self.verticesPerSide)
        var writeAt = 0
        for row in 0 ..< Self.segmentsPerSide {
            for col in 0 ..< Self.segmentsPerSide {
                let i00 = UInt32(row)        * perRow + UInt32(col)
                let i10 = UInt32(row)        * perRow + UInt32(col + 1)
                let i01 = UInt32(row + 1)    * perRow + UInt32(col)
                let i11 = UInt32(row + 1)    * perRow + UInt32(col + 1)
                // Triangle 1: (i00, i01, i11) — counter-clockwise from +Y.
                idxPtr[writeAt + 0] = i00
                idxPtr[writeAt + 1] = i01
                idxPtr[writeAt + 2] = i11
                // Triangle 2: (i00, i11, i10).
                idxPtr[writeAt + 3] = i00
                idxPtr[writeAt + 4] = i11
                idxPtr[writeAt + 5] = i10
                writeAt += 6
            }
        }

        // ── Build pipeline state ─────────────────────────────────────
        guard let vertFn = library.makeFunction(name: "ferrofluid_mesh_vertex") else {
            meshLogger.error("FerrofluidMesh: ferrofluid_mesh_vertex function not found")
            return nil
        }
        guard let fragFn = library.makeFunction(name: "ferrofluid_mesh_gbuffer_fragment") else {
            meshLogger.error("FerrofluidMesh: ferrofluid_mesh_gbuffer_fragment function not found")
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Ferrofluid Mesh G-buffer"
        desc.vertexFunction = vertFn
        desc.fragmentFunction = fragFn

        // Vertex descriptor — attribute 0 = position (float3), attribute 1 = uv (float2).
        // Mesh vertex buffer lives at slot 16 to avoid collision with the
        // `[[buffer(0)]]` FeatureVector / `[[buffer(3)]]` StemFeatures /
        // `[[buffer(4)]]` SceneUniforms binding slots in the vertex shader.
        // Metal's stage_in + [[buffer(N)]] mechanisms share the same binding
        // table, so the mesh vertex buffer's slot must be distinct from any
        // [[buffer(N)]] declared in the shader signature.
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = Self.kVertexBufferSlot
        vd.attributes[1].format = .float2
        vd.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vd.attributes[1].bufferIndex = Self.kVertexBufferSlot
        vd.layouts[Self.kVertexBufferSlot].stride = MemoryLayout<Vertex>.stride
        vd.layouts[Self.kVertexBufferSlot].stepFunction = .perVertex
        desc.vertexDescriptor = vd

        // G-buffer attachment formats — must match RayMarchPipeline's
        // gbuffer0 / gbuffer1 / gbuffer2 texture formats.
        for (i, fmt) in colorAttachmentFormats.enumerated() {
            desc.colorAttachments[i].pixelFormat = fmt
        }

        // Depth attachment so triangle occlusion resolves correctly.
        // (The SDF path doesn't use a depth attachment — depth is encoded
        // analytically in gbuffer0.r — but the mesh path overlaps triangles
        // and needs hardware depth test.)
        desc.depthAttachmentPixelFormat = depthAttachmentFormat

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            meshLogger.error("FerrofluidMesh: pipeline state creation failed: \(error)")
            return nil
        }

        // Depth-test state — closest fragment wins, depth write enabled.
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled  = true
        guard let dss = device.makeDepthStencilState(descriptor: dsd) else {
            meshLogger.error("FerrofluidMesh: depth-stencil state creation failed")
            return nil
        }
        self.depthStencilState = dss
    }

    // MARK: - Per-frame vertex uniforms (Phase 1 round 20)

    /// Mirror of `FerrofluidMeshUniforms` in FerrofluidMesh.metal.
    /// `tempoScale = bpm / 60` (beats per second); 0 at silence /
    /// pre-grid-lock state. Bound at vertex `[[buffer(5)]]`.
    public struct MeshUniforms {
        public var tempoScale: Float
        public var pad0: Float
        public var pad1: Float
        public var pad2: Float

        public init(tempoScale: Float) {
            self.tempoScale = tempoScale
            self.pad0 = 0
            self.pad1 = 0
            self.pad2 = 0
        }
    }

    // MARK: - Encode
    //
    // `encodeGBufferPass` takes six explicit binding-point parameters —
    // encoder, features, stems, sceneUniforms, meshUniforms, heightTexture.
    // Bundling them into a struct would obscure the binding contract.

    // swiftlint:disable function_parameter_count

    /// Encode the G-buffer pass for the ferrofluid mesh into `encoder`.
    /// Caller is responsible for the render pass descriptor + encoder
    /// lifecycle (begin / end); this method only sets pipeline state +
    /// buffers + textures + issues the indexed draw call.
    ///
    /// `meshUniforms` carries the per-frame vertex-stage uniforms —
    /// currently just `tempoScale` (CPU-computed from live BPM).
    public func encodeGBufferPass(into encoder: MTLRenderCommandEncoder,
                                  features: inout FeatureVector,
                                  stems: inout StemFeatures,
                                  sceneUniforms: inout SceneUniforms,
                                  meshUniforms: inout MeshUniforms,
                                  heightTexture: MTLTexture) {
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Vertex stage bindings. Mesh vertex buffer at slot 16 (matches
        // the vertex descriptor's bufferIndex); uniforms at slots 0/3/4/5.
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: Self.kVertexBufferSlot)
        encoder.setVertexBytes(&features,
                               length: MemoryLayout<FeatureVector>.stride,
                               index: 0)
        encoder.setVertexBytes(&stems,
                               length: MemoryLayout<StemFeatures>.stride,
                               index: 3)
        encoder.setVertexBytes(&sceneUniforms,
                               length: MemoryLayout<SceneUniforms>.stride,
                               index: 4)
        encoder.setVertexBytes(&meshUniforms,
                               length: MemoryLayout<MeshUniforms>.stride,
                               index: 5)
        encoder.setVertexTexture(heightTexture, index: 10)

        // Fragment stage bindings:
        //   SceneUniforms (slot 4) — depth normalization
        //   heightTexture (slot 10) — round-41 per-pixel normal computation
        //     samples the spike heightmap at the pixel's interpolated UV,
        //     bypassing the rasterizer's linear interpolation of the
        //     vertex-stage normal (which exposed mesh polygon facets once
        //     curtain edges sharpened).
        encoder.setFragmentBytes(&sceneUniforms,
                                 length: MemoryLayout<SceneUniforms>.stride,
                                 index: 4)
        encoder.setFragmentTexture(heightTexture, index: 10)

        encoder.drawIndexedPrimitives(type: .triangle,
                                       indexCount: Self.indexCount,
                                       indexType: .uint32,
                                       indexBuffer: indexBuffer,
                                       indexBufferOffset: 0)
    }

    // swiftlint:enable function_parameter_count
}
