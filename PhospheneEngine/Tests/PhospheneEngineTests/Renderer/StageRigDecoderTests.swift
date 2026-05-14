// StageRigDecoderTests — V.9 Session 4 Phase 0 backfill for the §5.8 / D-125
// stage-rig descriptor decode contract.
//
// Session 3 shipped the `PresetDescriptor.StageRig` JSON-decoder with a
// warn-and-clamp light_count branch and a warn-and-truncate/pad
// palette_phase_offsets branch but did NOT regression-lock the decoder
// behaviour with unit tests. This file closes that gap.
//
// Tests:
//   1. light_count = 4 (canonical) → decodes cleanly, all fields present.
//   2. light_count = 2 / 7 / -1 / 99 → clamps to 4 (the §5.8 baseline).
//   3. palette_phase_offsets matching light_count → passes through unchanged.
//   4. palette_phase_offsets shorter than light_count → pads with evenly-spaced
//      offsets (i / lightCount for the missing tail).
//   5. palette_phase_offsets longer than light_count → truncates to the first
//      light_count entries.
//   6. Round-trip via JSONEncoder → JSONDecoder preserves all fields (the
//      synthesised Codable encoder side stays in sync with the custom decoder).
//
// Mirrors the structural conventions of `PresetDescriptorMetadataTests`.

import Testing
import Foundation
@testable import Presets

// MARK: - 1. Canonical light_count = 4

@Test func stageRig_lightCountFour_decodesCleanly() throws {
    let json = """
    {
        "name": "RigCanonical",
        "stage_rig": {
            "light_count": 4,
            "orbit_altitude": 6.0,
            "orbit_radius": 4.0,
            "orbit_speed_baseline": 0.05,
            "orbit_speed_arousal_coef": 0.15,
            "palette_phase_offsets": [0.0, 0.33, 0.67, 0.17],
            "intensity_baseline": 5.0,
            "intensity_floor_coef": 0.4,
            "intensity_swing_coef": 0.6,
            "intensity_smoothing_tau_ms": 150
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4)
    #expect(rig.orbitAltitude == 6.0)
    #expect(rig.orbitRadius == 4.0)
    #expect(rig.orbitSpeedBaseline == 0.05)
    #expect(rig.orbitSpeedArousalCoef == 0.15)
    #expect(rig.palettePhaseOffsets.count == 4)
    #expect(rig.palettePhaseOffsets[0] == 0.0)
    #expect(rig.palettePhaseOffsets[1] == 0.33)
    #expect(rig.palettePhaseOffsets[2] == 0.67)
    #expect(rig.palettePhaseOffsets[3] == 0.17)
    #expect(rig.intensityBaseline == 5.0)
    #expect(rig.intensityFloorCoef == 0.4)
    #expect(rig.intensitySwingCoef == 0.6)
    #expect(rig.intensitySmoothingTauMs == 150)
}

// MARK: - 2. Out-of-range light_count clamps to 4

@Test func stageRig_lightCountTooLow_clampsToFour() throws {
    let json = """
    { "name": "RigLow", "stage_rig": { "light_count": 2 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4, "light_count=2 (below [3, 6]) should clamp to 4")
}

@Test func stageRig_lightCountTooHigh_clampsToFour() throws {
    let json = """
    { "name": "RigHigh", "stage_rig": { "light_count": 7 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4, "light_count=7 (above [3, 6]) should clamp to 4")
}

@Test func stageRig_lightCountNegative_clampsToFour() throws {
    let json = """
    { "name": "RigNeg", "stage_rig": { "light_count": -1 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4, "light_count=-1 should clamp to 4")
}

@Test func stageRig_lightCountAbsurdlyHigh_clampsToFour() throws {
    let json = """
    { "name": "RigAbsurd", "stage_rig": { "light_count": 99 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4, "light_count=99 should clamp to 4")
}

// MARK: - 3. palette_phase_offsets length == light_count → pass through

@Test func stageRig_paletteOffsetsExactLength_passThrough() throws {
    let json = """
    {
        "name": "RigExact",
        "stage_rig": {
            "light_count": 5,
            "palette_phase_offsets": [0.1, 0.3, 0.5, 0.7, 0.9]
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 5)
    #expect(rig.palettePhaseOffsets == [0.1, 0.3, 0.5, 0.7, 0.9])
}

// MARK: - 4. palette_phase_offsets shorter than light_count → pad

@Test func stageRig_paletteOffsetsShorter_padsWithEvenlySpaced() throws {
    // light_count = 4, but only 2 offsets supplied. Pad with i/N for the
    // missing tail — at index 2 the padded value is 2/4 = 0.5; at 3 it's
    // 3/4 = 0.75. The decoder uses `offsets.count + i` for the tail index,
    // so the first existing offsets stay in place, and the padded values
    // start where the missing slots begin.
    let json = """
    {
        "name": "RigShort",
        "stage_rig": {
            "light_count": 4,
            "palette_phase_offsets": [0.0, 0.25]
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 4)
    #expect(rig.palettePhaseOffsets.count == 4, "should pad to light_count length")
    #expect(rig.palettePhaseOffsets[0] == 0.0)
    #expect(rig.palettePhaseOffsets[1] == 0.25)
    // Padded slots: index 2 → 2/4 = 0.5; index 3 → 3/4 = 0.75.
    #expect(rig.palettePhaseOffsets[2] == 0.5,
            "padded slot at index 2 should be 2/4 = 0.5, got \(rig.palettePhaseOffsets[2])")
    #expect(rig.palettePhaseOffsets[3] == 0.75,
            "padded slot at index 3 should be 3/4 = 0.75, got \(rig.palettePhaseOffsets[3])")
}

// MARK: - 5. palette_phase_offsets longer than light_count → truncate

@Test func stageRig_paletteOffsetsLonger_truncates() throws {
    let json = """
    {
        "name": "RigLong",
        "stage_rig": {
            "light_count": 3,
            "palette_phase_offsets": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        }
    }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 3)
    #expect(rig.palettePhaseOffsets.count == 3, "should truncate to light_count")
    #expect(rig.palettePhaseOffsets == [0.1, 0.2, 0.3])
}

// MARK: - 6. Codable round-trip — synthesized encoder matches custom decoder

@Test func stageRig_codableRoundTrip_preservesAllFields() throws {
    let json = """
    {
        "name": "RigRoundTrip",
        "stage_rig": {
            "light_count": 5,
            "orbit_altitude": 7.5,
            "orbit_radius": 3.25,
            "orbit_speed_baseline": 0.08,
            "orbit_speed_arousal_coef": 0.22,
            "palette_phase_offsets": [0.05, 0.27, 0.49, 0.71, 0.93],
            "intensity_baseline": 6.5,
            "intensity_floor_coef": 0.35,
            "intensity_swing_coef": 0.65,
            "intensity_smoothing_tau_ms": 200
        }
    }
    """
    let decoder = JSONDecoder()
    let first = try decoder.decode(PresetDescriptor.self, from: Data(json.utf8))
    let encoder = JSONEncoder()
    let reencoded = try encoder.encode(first)
    let second = try decoder.decode(PresetDescriptor.self, from: reencoded)

    let rigA = try #require(first.stageRig)
    let rigB = try #require(second.stageRig)
    #expect(rigA == rigB, "Codable round-trip must preserve all StageRig fields")
    #expect(rigB.lightCount == 5)
    #expect(rigB.orbitAltitude == 7.5)
    #expect(rigB.orbitRadius == 3.25)
    #expect(rigB.orbitSpeedBaseline == 0.08)
    #expect(rigB.orbitSpeedArousalCoef == 0.22)
    #expect(rigB.palettePhaseOffsets == [0.05, 0.27, 0.49, 0.71, 0.93])
    #expect(rigB.intensityBaseline == 6.5)
    #expect(rigB.intensityFloorCoef == 0.35)
    #expect(rigB.intensitySwingCoef == 0.65)
    #expect(rigB.intensitySmoothingTauMs == 200)
}

// MARK: - 7. Missing stage_rig block → nil

@Test func stageRig_missingBlock_decodesAsNil() throws {
    let json = """
    { "name": "NoRig" }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.stageRig == nil,
            "Absent stage_rig block should decode as nil (legacy path)")
}

// MARK: - 8. Partial stage_rig block → defaults applied

@Test func stageRig_partialBlock_appliesDefaults() throws {
    // Only light_count + orbit_radius supplied — everything else takes the
    // §5.8 spec defaults from the public memberwise init.
    let json = """
    { "name": "PartialRig", "stage_rig": { "light_count": 3, "orbit_radius": 5.0 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    let rig = try #require(descriptor.stageRig)
    #expect(rig.lightCount == 3)
    #expect(rig.orbitRadius == 5.0)
    #expect(rig.orbitAltitude == 6.0, "default orbit_altitude")
    #expect(rig.orbitSpeedBaseline == 0.05, "default orbit_speed_baseline")
    #expect(rig.orbitSpeedArousalCoef == 0.15, "default orbit_speed_arousal_coef")
    #expect(rig.intensityBaseline == 5.0, "default intensity_baseline")
    #expect(rig.intensityFloorCoef == 0.4, "default intensity_floor_coef")
    #expect(rig.intensitySwingCoef == 0.6, "default intensity_swing_coef")
    #expect(rig.intensitySmoothingTauMs == 150, "default tau (ms)")
    // palette_phase_offsets defaulted to [] → padded to light_count via the
    // decoder's mismatch branch — three evenly-spaced offsets at 0/3, 1/3, 2/3.
    #expect(rig.palettePhaseOffsets.count == 3,
            "partial block should pad palette_phase_offsets to light_count")
}
