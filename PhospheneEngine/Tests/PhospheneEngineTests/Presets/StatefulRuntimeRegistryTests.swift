// StatefulRuntimeRegistryTests — R2 (PUB.8) rename gate for stateful-preset
// runtimes. The app's bindStatefulPresetRuntime(for:) dispatches by display
// name; a sidecar rename without a switch update silently loses the preset's
// CPU-side runtime (state buffers stay zeroed → black/static). This locks
// every registered name to a shipped sidecar.

import Testing
import Metal
@testable import Renderer
@testable import Presets

@Suite("StatefulRuntimeRegistry")
struct StatefulRuntimeRegistryTests {

    @Test("every registered stateful-runtime name matches a shipped sidecar")
    func test_registeredNamesMatchShippedPresets() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("StatefulRuntimeRegistryTests: no Metal device — skipping")
            return
        }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let shippedNames = Set(loader.presets.map(\.descriptor.name))
        for name in StatefulRuntimeRegistry.knownPresetNames {
            #expect(shippedNames.contains(name), """
                StatefulRuntimeRegistry lists '\(name)' but no shipped sidecar \
                carries that display name — a rename must update BOTH the \
                sidecar and bindStatefulPresetRuntime(for:) + this registry.
                """)
        }
    }
}
