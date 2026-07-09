// AudioRouteSchemaTests — QG.1 schema gate for the `audio_routes` sidecar manifest.
//
// Two invariants over the real shipped sidecar corpus:
//   1. Every declared `audio_routes[].primitive` is a known, session-recordable
//      field (`AudioRoutePrimitives.map`). A typo or a field with no CSV column
//      fails here — before RouteCoverageTests, which could not resolve it at all.
//   2. Every declared `kind` is a known `AudioRoute.Kind` (the decoder would
//      otherwise throw; this asserts the corpus is clean).
//
// Enumerates sidecars via `PresetLoader.bundledShadersURL` (the Presets-module
// accessor — `Bundle.module` from the test target resolves to the test bundle,
// which has no Shaders resource; BUG-002 / NACRE.6).

import Foundation
import Testing
@testable import Presets

struct AudioRouteSchemaTests {

    @Test("audio_routes primitives are all session-recordable (QG.1 schema gate)")
    func audioRoutePrimitivesAreKnown() throws {
        let shadersURL = try #require(PresetLoader.bundledShadersURL,
            "Shaders resource not found via PresetLoader.bundledShadersURL")
        let jsonFiles = try FileManager.default.contentsOfDirectory(
            at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        #expect(jsonFiles.count >= 13, "Expected at least 13 JSON sidecars")

        let decoder = JSONDecoder()
        var unknown: [String] = []
        for jsonURL in jsonFiles {
            let name = jsonURL.lastPathComponent
            let descriptor: PresetDescriptor
            do {
                descriptor = try decoder.decode(PresetDescriptor.self,
                                                from: try Data(contentsOf: jsonURL))
            } catch {
                Issue.record("\(name): decode failed — \(error)")
                continue
            }
            for route in descriptor.audioRoutes where !AudioRoutePrimitives.isValid(route.primitive) {
                unknown.append("\(name): route '\(route.route)' → unknown primitive '\(route.primitive)'")
            }
        }
        let joined = unknown.joined(separator: "; ")
        #expect(unknown.isEmpty,
                "audio_routes reference primitives with no recordable CSV column (typo, or a field the session recorder does not write): \(joined)")
    }

    @Test("A typo'd primitive is rejected (guards the guard)")
    func unknownPrimitiveIsInvalid() {
        #expect(AudioRoutePrimitives.isValid("bassDev"))
        #expect(AudioRoutePrimitives.isValid("drumsEnergyDev"))
        #expect(AudioRoutePrimitives.isValid("barPhase01"))
        #expect(!AudioRoutePrimitives.isValid("bassDevv"))
        #expect(!AudioRoutePrimitives.isValid("frame_cpu_ms"))   // perf column, not a route
        #expect(!AudioRoutePrimitives.isValid("time"))           // clock, not a route
    }

    @Test("An unknown kind fails to decode")
    func unknownKindThrows() {
        let json = Data("""
        { "route": "x", "primitive": "bass", "kind": "wobble" }
        """.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PresetDescriptor.AudioRoute.self, from: json)
        }
    }
}
