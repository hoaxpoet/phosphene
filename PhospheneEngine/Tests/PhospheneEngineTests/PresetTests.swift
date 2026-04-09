// PresetTests — Unit tests for PresetDescriptor JSON parsing and PresetCategory.

import Testing
import Foundation
@testable import Presets

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
