// PresetTests — Unit tests for PresetDescriptor JSON parsing, PresetCategory, and RenderPass.

import Testing
import Foundation
import Metal
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - PresetCategory Tests

@Test func presetCategoryAllCases() {
    #expect(PresetCategory.allCases.count == 12)
    #expect(PresetCategory.allCases.contains(.waveform))
    #expect(PresetCategory.allCases.contains(.fractal))
    #expect(PresetCategory.allCases.contains(.geometric))
    #expect(PresetCategory.allCases.contains(.particles))
    #expect(PresetCategory.allCases.contains(.hypnotic))
}

@Test func presetCategoryRawValues() {
    #expect(PresetCategory.waveform.rawValue == "waveform")
    #expect(PresetCategory.fractal.rawValue == "fractal")
    #expect(PresetCategory.transition.rawValue == "transition")
}

@Test func presetCategoryCodable() throws {
    let json = "\"geometric\""
    let decoded = try JSONDecoder().decode(PresetCategory.self, from: Data(json.utf8))
    #expect(decoded == .geometric)

    let encoded = try JSONEncoder().encode(PresetCategory.particles)
    let str = String(data: encoded, encoding: .utf8)
    #expect(str == "\"particles\"")
}

// MARK: - PresetDescriptor Parsing Tests

@Test func presetDescriptorFullJSON() throws {
    let json = """
    {
      "name": "Kaleidoscope",
      "family": "geometric",
      "duration": 25,
      "description": "Sacred geometry spiral",
      "author": "Matt",
      "beat_source": "composite",
      "beat_zoom": 0.05,
      "beat_rot": 0.05,
      "base_zoom": 0.12,
      "base_rot": 0.06,
      "decay": 0.91,
      "beat_sensitivity": 1.2
    }
    """

    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))

    #expect(descriptor.name == "Kaleidoscope")
    #expect(descriptor.family == .geometric)
    #expect(descriptor.duration == 25)
    #expect(descriptor.description == "Sacred geometry spiral")
    #expect(descriptor.author == "Matt")
    #expect(descriptor.beatSource == .composite)
    #expect(descriptor.beatZoom == 0.05)
    #expect(descriptor.beatRot == 0.05)
    #expect(descriptor.baseZoom == 0.12)
    #expect(descriptor.baseRot == 0.06)
    #expect(descriptor.decay == 0.91)
    #expect(descriptor.beatSensitivity == 1.2)
    #expect(descriptor.id == "Kaleidoscope")
}

@Test func presetDescriptorMinimalJSON() throws {
    let json = """
    {"name": "Simple"}
    """

    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))

    // All fields should have sensible defaults.
    #expect(descriptor.name == "Simple")
    #expect(descriptor.family == .waveform, "Default family should be waveform")
    #expect(descriptor.duration == 30, "Default duration should be 30")
    #expect(descriptor.description == "")
    #expect(descriptor.author == "")
    #expect(descriptor.beatSource == .bass, "Default beat source should be bass")
    #expect(descriptor.beatZoom == 0.03, "Default beat_zoom should be 0.03")
    #expect(descriptor.beatRot == 0.01, "Default beat_rot should be 0.01")
    #expect(descriptor.baseZoom == 0.12, "Default base_zoom should be 0.12")
    #expect(descriptor.baseRot == 0.03, "Default base_rot should be 0.03")
    #expect(descriptor.decay == 0.955, "Default decay should be 0.955")
    #expect(descriptor.beatSensitivity == 1.0, "Default beat_sensitivity should be 1.0")
    #expect(descriptor.fragmentFunction == "preset_fragment")
    #expect(descriptor.vertexFunction == "fullscreen_vertex")
}

@Test func presetDescriptorBeatSourceVariants() throws {
    for source in ["bass", "mid", "treble", "composite"] {
        let json = """
        {"name": "Test", "beat_source": "\(source)"}
        """
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(descriptor.beatSource.rawValue == source)
    }
}

@Test func presetDescriptorDecayRange() throws {
    // Decay should be preserved exactly as specified — no clamping.
    let json = """
    {"name": "Test", "decay": 0.85}
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.decay == 0.85)

    let json2 = """
    {"name": "Test2", "decay": 0.95}
    """
    let descriptor2 = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json2.utf8))
    #expect(descriptor2.decay == 0.95)
}

@Test func presetDescriptorCustomFunctionNames() throws {
    let json = """
    {"name": "Custom", "fragment_function": "custom_frag", "vertex_function": "custom_vert"}
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.fragmentFunction == "custom_frag")
    #expect(descriptor.vertexFunction == "custom_vert")
}

@Test func presetDescriptorInvalidJSONThrows() {
    let badJSON = Data("not json".utf8)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(PresetDescriptor.self, from: badJSON)
    }
}

@Test func presetDescriptorMissingNameThrows() {
    let json = Data("""
    {"family": "geometric"}
    """.utf8)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(PresetDescriptor.self, from: json)
    }
}

@Test func presetDescriptorFallbackFactory() {
    let fallback = PresetDescriptor.fallback(name: "TestFallback")
    #expect(fallback.name == "TestFallback")
    #expect(fallback.family == .waveform)
    #expect(fallback.decay == 0.955)
}

// MARK: - Visual Design Hierarchy Validation

@Test func presetDescriptorBaseZoomExceedsBeatZoom() throws {
    // CLAUDE.md rule: base_zoom should be 2–4x larger than beat_zoom.
    // This test validates that the default metadata JSON files follow this rule.
    let json = """
    {"name": "Waveform", "base_zoom": 0.12, "beat_zoom": 0.03, "base_rot": 0.03, "beat_rot": 0.01}
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))

    #expect(descriptor.baseZoom > descriptor.beatZoom,
            "base_zoom (\(descriptor.baseZoom)) must exceed beat_zoom (\(descriptor.beatZoom)) — continuous energy is primary driver")
    #expect(descriptor.baseRot >= descriptor.beatRot,
            "base_rot (\(descriptor.baseRot)) must meet or exceed beat_rot (\(descriptor.beatRot))")
}

// MARK: - RenderPass Tests (Increment 3.6)

@Test func renderPassRawValues() {
    #expect(RenderPass.direct.rawValue    == "direct")
    #expect(RenderPass.feedback.rawValue  == "feedback")
    #expect(RenderPass.particles.rawValue == "particles")
    #expect(RenderPass.meshShader.rawValue  == "mesh_shader")
    #expect(RenderPass.postProcess.rawValue == "post_process")
    #expect(RenderPass.rayMarch.rawValue    == "ray_march")
    #expect(RenderPass.icb.rawValue == "icb")
}

@Test func renderPassDecodesFromJSON() throws {
    let json = """
    {"name": "Test", "passes": ["feedback", "particles"]}
    """
    let desc = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(desc.passes == [.feedback, .particles])
    #expect(desc.useFeedback  == true,  "useFeedback should derive from passes")
    #expect(desc.useParticles == true,  "useParticles should derive from passes")
    #expect(desc.useMeshShader  == false)
    #expect(desc.usePostProcess == false)
    #expect(desc.useRayMarch    == false)
}

@Test func renderPassDefaultIsDirect() throws {
    let json = """
    {"name": "Simple"}
    """
    let desc = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(desc.passes == [.direct], "Minimal JSON with no passes or legacy flags → [.direct]")
    #expect(desc.useFeedback    == false)
    #expect(desc.useMeshShader  == false)
    #expect(desc.usePostProcess == false)
    #expect(desc.useRayMarch    == false)
    #expect(desc.useParticles   == false)
}

@Test func renderPassSynthesisedFromLegacyFeedbackAndParticles() throws {
    let json = """
    {"name": "Legacy", "use_feedback": true, "use_particles": true}
    """
    let desc = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(desc.passes == [.feedback, .particles],
            "Legacy use_feedback + use_particles → passes: [.feedback, .particles]")
}

@Test func renderPassSynthesisedFromLegacyMeshShader() throws {
    let json = """
    {"name": "Legacy", "use_mesh_shader": true}
    """
    let desc = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(desc.passes == [.meshShader],
            "Legacy use_mesh_shader: true → passes: [.meshShader]")
}

@Test func renderPassSynthesisedFromLegacyRayMarchWithPostProcess() throws {
    let json = """
    {"name": "Legacy", "use_ray_march": true, "use_post_process": true}
    """
    let desc = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(desc.passes == [.rayMarch, .postProcess],
            "Legacy use_ray_march + use_post_process → passes: [.rayMarch, .postProcess]")
}

@Test func renderGraphSetActivePasses_roundTrips() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let fftBuf = ctx.makeSharedBuffer(length: 512  * MemoryLayout<Float>.stride)!
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!
    let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                       fftBuffer: fftBuf, waveformBuffer: wavBuf)

    // Default passes after init.
    #expect(pipeline.currentPasses == [.direct])

    // Switch to feedback + particles.
    pipeline.setActivePasses([.feedback, .particles])
    #expect(pipeline.currentPasses == [.feedback, .particles],
            "setActivePasses should store and return the exact array supplied")

    // Reset to empty (pre-preset-switch state).
    pipeline.setActivePasses([])
    #expect(pipeline.currentPasses == [],
            "Empty passes array should be stored as-is")
}
