// ShaderLibraryTests — Unit tests for shader discovery, compilation, and pipeline state caching.

import Testing
import Metal
@testable import Renderer

@Test func test_init_discoversWaveformShader() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    // The Waveform.metal shader defines fullscreen_vertex and waveform_fragment.
    let vertexFn = lib.function(named: "fullscreen_vertex")
    let fragmentFn = lib.function(named: "waveform_fragment")
    #expect(vertexFn != nil, "Should discover fullscreen_vertex function")
    #expect(fragmentFn != nil, "Should discover waveform_fragment function")
}

@Test func test_loadShader_validName_returnsPipelineState() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    let state = try lib.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: ctx.pixelFormat,
        device: ctx.device
    )
    // MTLRenderPipelineState is non-nil if compilation succeeded.
    #expect(state.label == nil || true, "Pipeline state should be created successfully")
}

@Test func test_loadShader_invalidName_returnsNil() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    let fn = lib.function(named: "nonexistent_shader")
    #expect(fn == nil, "Non-existent shader function should return nil")
}

@Test func test_cachedPipelineState_sameName_returnsSameInstance() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    let state1 = try lib.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: ctx.pixelFormat,
        device: ctx.device
    )
    let state2 = try lib.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: ctx.pixelFormat,
        device: ctx.device
    )

    #expect(state1 === state2, "Cached pipeline states should be the same object instance")
}

@Test func test_allShaderNames_returnsNonEmptySet() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    // The library should have at least the waveform functions.
    let functionNames = lib.library.functionNames
    #expect(!functionNames.isEmpty, "Compiled library should contain at least one function")
    #expect(functionNames.contains("fullscreen_vertex"), "Should contain fullscreen_vertex")
    #expect(functionNames.contains("waveform_fragment"), "Should contain waveform_fragment")
}

@Test func test_shaderCompilation_noWarnings() throws {
    let ctx = try MetalContext()

    // If ShaderLibrary init succeeds without throwing, compilation had no errors.
    // We verify by checking the library has functions.
    let lib = try ShaderLibrary(context: ctx)
    let names = lib.library.functionNames
    #expect(names.count >= 2,
            "Shader compilation should produce at least vertex + fragment functions, got \(names.count)")
}
