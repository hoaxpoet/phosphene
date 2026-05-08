// ParticleDispatchRegistryTests — Lock the catalog↔registry consistency
// for `.particles`-pass presets (DM.1).
//
// Closes the silent-fall-through hole: `applyPreset .particles:` resolves
// the conformer by preset name. A typo in a JSON sidecar (or a new
// particle preset whose name was added to the catalog but not to
// `ParticleGeometryRegistry.knownPresetNames`) would silently render the
// preset's backdrop with no particles. This test walks every loaded
// preset whose `passes` contains `.particles` and asserts its name is
// registered.

import Testing
import Metal
@testable import Renderer
@testable import Presets
import Shared

@Suite("ParticleDispatchRegistry")
struct ParticleDispatchRegistryTests {

    @Test("every .particles-pass preset is registered in ParticleGeometryRegistry")
    func test_everyParticlesPresetIsRegistered() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ParticleDispatchRegistryTests: no Metal device — skipping")
            return
        }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let particlePresets = loader.presets.filter { $0.descriptor.passes.contains(.particles) }

        // The catalog must declare at least the two known particle presets;
        // an empty result here means the catalog regressed (e.g. silent
        // shader-compile drop hit Murmuration or Drift Motes).
        #expect(!particlePresets.isEmpty,
                "No presets with .particles pass were loaded — catalog regressed")

        for preset in particlePresets {
            let name = preset.descriptor.name
            #expect(ParticleGeometryRegistry.knownPresetNames.contains(name), """
                Preset '\(name)' has the .particles render pass but is not \
                listed in ParticleGeometryRegistry.knownPresetNames. Add it \
                there, register the geometry factory in \
                VisualizerEngine.init, and add the dispatch case in \
                VisualizerEngine.resolveParticleGeometry. Otherwise \
                applyPreset will silently fall through and the preset will \
                render its backdrop with no particles.
                """)
        }
    }

    @Test("DriftMotesGeometry.presetName is registered")
    func test_driftMotesPresetNameRegistered() {
        #expect(ParticleGeometryRegistry.knownPresetNames.contains(DriftMotesGeometry.presetName))
    }

    @Test("Murmuration is registered")
    func test_murmurationRegistered() {
        #expect(ParticleGeometryRegistry.knownPresetNames.contains("Murmuration"))
    }
}
