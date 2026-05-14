// FerrofluidParamsDecoderTests — V.9 Session 4.5 Phase 0 regression gate for
// the `ferrofluid` JSON block decode contract (D-124).
//
// Session 4 schema (5 fields driving 4 detail layers) was reduced to 2 fields
// in Session 4.5 Phase 0 after M7 review rejected the droplet / meso warp /
// micro-normal decoration layers (Failed Approach #62). Only the audio-
// modulated thin-film thickness remains.
//
// Tests:
//   1. Full block — both fields decode to the JSON-supplied value.
//   2. Empty block — both fields fall back to the documented default.
//   3. Missing block — ferrofluid property is nil.
//   4. Partial block — only supplied field takes JSON; the other takes default.
//   5. Negative values — warn-and-floor to the documented default.
//   6. Codable round-trip — synthesised encoder matches custom decoder.
//   7. On-disk back-fill — FerrofluidOcean.json's ferrofluid block decodes
//      with the expected V.9 Session 4.5 spec values, proving the schema is
//      in place on the production preset.

import Testing
import Foundation
import Metal
@testable import Presets

private enum FerrofluidDecoderTestError: Error { case noMetalDevice }

// MARK: - 1. Full block

@Test func ferrofluidParams_fullBlock_decodesAllFields() throws {
    let json = """
    {
        "name": "FerroFull",
        "ferrofluid": {
            "thin_film_thickness_baseline_nm": 210,
            "thin_film_arousal_range_nm": 35
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let params = try #require(descriptor.ferrofluid)
    #expect(params.thinFilmThicknessBaselineNm == 210)
    #expect(params.thinFilmArousalRangeNm == 35)
}

// MARK: - 2. Empty block → defaults

@Test func ferrofluidParams_emptyBlock_usesDefaults() throws {
    let json = """
    { "name": "FerroEmpty", "ferrofluid": {} }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let params = try #require(descriptor.ferrofluid)
    #expect(params.thinFilmThicknessBaselineNm == 220)
    #expect(params.thinFilmArousalRangeNm == 40)
}

// MARK: - 3. Missing block → nil

@Test func ferrofluidParams_missingBlock_isNil() throws {
    let json = """
    { "name": "NoFerro" }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.ferrofluid == nil,
            "Absent ferrofluid block should decode as nil")
}

// MARK: - 4. Partial block → mix of JSON + defaults

@Test func ferrofluidParams_partialBlock_appliesDefaults() throws {
    let json = """
    { "name": "FerroPartial", "ferrofluid": { "thin_film_thickness_baseline_nm": 200 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let params = try #require(descriptor.ferrofluid)
    #expect(params.thinFilmThicknessBaselineNm == 200, "supplied value preserved")
    #expect(params.thinFilmArousalRangeNm == 40, "default thin_film_arousal_range_nm")
}

// MARK: - 5. Negative values → warn-and-floor

@Test func ferrofluidParams_negativeValues_floorToDefault() throws {
    let json = """
    {
        "name": "FerroNegative",
        "ferrofluid": {
            "thin_film_thickness_baseline_nm": -100,
            "thin_film_arousal_range_nm": -20
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let params = try #require(descriptor.ferrofluid)
    #expect(params.thinFilmThicknessBaselineNm == 220,
            "negative thin_film_thickness_baseline_nm should floor to default 220")
    #expect(params.thinFilmArousalRangeNm == 40,
            "negative thin_film_arousal_range_nm should floor to default 40")
}

// MARK: - 6. Codable round-trip

@Test func ferrofluidParams_codableRoundTrip_preservesAllFields() throws {
    let json = """
    {
        "name": "FerroRoundTrip",
        "ferrofluid": {
            "thin_film_thickness_baseline_nm": 230,
            "thin_film_arousal_range_nm": 45
        }
    }
    """
    let decoder = JSONDecoder()
    let first = try decoder.decode(PresetDescriptor.self, from: Data(json.utf8))
    let encoder = JSONEncoder()
    let reencoded = try encoder.encode(first)
    let second = try decoder.decode(PresetDescriptor.self, from: reencoded)

    let pA = try #require(first.ferrofluid)
    let pB = try #require(second.ferrofluid)
    #expect(pA == pB, "Codable round-trip must preserve all FerrofluidParams fields")
    #expect(pB.thinFilmThicknessBaselineNm == 230)
    #expect(pB.thinFilmArousalRangeNm == 45)
}

// MARK: - 7. On-disk back-fill — production FerrofluidOcean.json carries the block

@Test func ferrofluidParams_productionPresetHasBlock() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FerrofluidDecoderTestError.noMetalDevice
    }
    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
    let preset = try #require(
        loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
        "Ferrofluid Ocean preset must exist for V.9 Session 4.5 Phase 0 back-fill check"
    )
    let params = try #require(preset.descriptor.ferrofluid,
                              "Ferrofluid Ocean's JSON must carry the V.9 Session 4.5 ferrofluid block")
    // V.9 Session 4.5 spec defaults — production preset uses the documented baseline.
    #expect(params.thinFilmThicknessBaselineNm == 220)
    #expect(params.thinFilmArousalRangeNm == 40)
}
