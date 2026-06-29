// ParticleDispatchRegistryTests — Lock the catalog↔registry consistency
// for `.particles`-pass presets.
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

        // The catalog must declare at least one known particle preset;
        // an empty result here means the catalog regressed (e.g. silent
        // shader-compile drop hit Murmuration).
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

    @Test("Murmuration is registered")
    func test_murmurationRegistered() {
        #expect(ParticleGeometryRegistry.knownPresetNames.contains("Murmuration"))
    }

    /// Mitosis loads as a real particles preset via the production load path
    /// (MITOSIS.1). Guards the silent-degrade regression: an invalid sidecar field
    /// (e.g. an out-of-enum `beat_source`) makes PresetLoader fall back to a default
    /// descriptor — dropping the `.particles` pass and the backdrop fragment — which
    /// would let `test_everyParticlesPresetIsRegistered` pass *vacuously*.
    @Test("Mitosis loads as a particles preset (sidecar not degraded)")
    func test_mitosisLoadsAsParticles() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ParticleDispatchRegistryTests: no Metal device — skipping")
            return
        }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        guard let mitosis = loader.presets.first(where: { $0.descriptor.name == "Mitosis" }) else {
            Issue.record("Mitosis preset did not load — sidecar malformed (degrades + drops) or shader-compile dropped it")
            return
        }
        #expect(mitosis.descriptor.passes.contains(.particles),
                "Mitosis must keep its .particles pass — a degraded default descriptor drops it")
        #expect(mitosis.descriptor.fragmentFunction == "mitosis_ground_fragment",
                "a degraded default descriptor falls back to 'preset_fragment'")
        #expect(ParticleGeometryRegistry.knownPresetNames.contains("Mitosis"))
    }
}
