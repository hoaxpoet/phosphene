import Metal

extension RayMarchPipeline {

    // MARK: - Pipeline Bundle

    struct PipelineBundle {
        var lighting: MTLRenderPipelineState
        var ssgi: MTLRenderPipelineState
        var ssgiBlend: MTLRenderPipelineState
        var composite: MTLRenderPipelineState
        var gbufferDebug: MTLRenderPipelineState
        var depthDebug: MTLRenderPipelineState
        var sampler: MTLSamplerState
    }

    static func buildPipelineBundle(
        context: MetalContext,
        shaderLibrary: ShaderLibrary
    ) throws -> PipelineBundle {
        let device = context.device
        let fns = try resolveFunctions(from: shaderLibrary)
        let descs = makeDescriptors(vertexFn: fns.vertex, context: context, fns: fns)
        let samp = try makeSampler(device: device)
        return PipelineBundle(
            lighting: try device.makeRenderPipelineState(descriptor: descs.light),
            ssgi: try device.makeRenderPipelineState(descriptor: descs.ssgi),
            ssgiBlend: try device.makeRenderPipelineState(descriptor: descs.ssgiBlend),
            composite: try device.makeRenderPipelineState(descriptor: descs.composite),
            gbufferDebug: try device.makeRenderPipelineState(descriptor: descs.gbufferDebug),
            depthDebug: try device.makeRenderPipelineState(descriptor: descs.depthDebug),
            sampler: samp
        )
    }

    private struct ResolvedFunctions {
        var vertex: MTLFunction
        var lighting: MTLFunction
        var ssgi: MTLFunction
        var ssgiBlend: MTLFunction
        var composite: MTLFunction
        var gbufferDebug: MTLFunction
        var depthDebug: MTLFunction
    }

    private struct PipelineDescriptors {
        var light: MTLRenderPipelineDescriptor
        var ssgi: MTLRenderPipelineDescriptor
        var ssgiBlend: MTLRenderPipelineDescriptor
        var composite: MTLRenderPipelineDescriptor
        var gbufferDebug: MTLRenderPipelineDescriptor
        var depthDebug: MTLRenderPipelineDescriptor
    }

    private static func resolveFunctions(from lib: ShaderLibrary) throws -> ResolvedFunctions {
        func fn(_ name: String) throws -> MTLFunction {
            guard let mtlFn = lib.function(named: name) else {
                throw RayMarchPipelineError.functionNotFound(name)
            }
            return mtlFn
        }
        return ResolvedFunctions(
            vertex: try fn("fullscreen_vertex"),
            lighting: try fn("raymarch_lighting_fragment"),
            ssgi: try fn("ssgi_fragment"),
            ssgiBlend: try fn("ssgi_blend_fragment"),
            composite: try fn("raymarch_composite_fragment"),
            gbufferDebug: try fn("raymarch_gbuffer_debug_fragment"),
            depthDebug: try fn("raymarch_depth_debug_fragment")
        )
    }

    private static func makeDescriptors(
        vertexFn: MTLFunction,
        context: MetalContext,
        fns: ResolvedFunctions
    ) -> PipelineDescriptors {
        func simple(_ frag: MTLFunction, format: MTLPixelFormat) -> MTLRenderPipelineDescriptor {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = format
            return desc
        }
        let ssgiBlendDesc = simple(fns.ssgiBlend, format: .rgba16Float)
        ssgiBlendDesc.colorAttachments[0].isBlendingEnabled = true
        ssgiBlendDesc.colorAttachments[0].rgbBlendOperation = .add
        ssgiBlendDesc.colorAttachments[0].alphaBlendOperation = .add
        ssgiBlendDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        return PipelineDescriptors(
            light: simple(fns.lighting, format: .rgba16Float),
            ssgi: simple(fns.ssgi, format: .rgba16Float),
            ssgiBlend: ssgiBlendDesc,
            composite: simple(fns.composite, format: context.pixelFormat),
            gbufferDebug: simple(fns.gbufferDebug, format: context.pixelFormat),
            depthDebug: simple(fns.depthDebug, format: context.pixelFormat)
        )
    }

    private static func makeSampler(device: MTLDevice) throws -> MTLSamplerState {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        guard let samp = device.makeSamplerState(descriptor: desc) else {
            throw RayMarchPipelineError.samplerCreationFailed
        }
        return samp
    }
}
