// DocsExampleCompileTests — the YOUR_FIRST_PRESET.md walkthrough pair must
// actually compile through the real PresetLoader (PUB.7). Docs-code drift
// gate in the DocIntegrity spirit: extracts the doc's fenced ```metal and
// ```json blocks at test time, writes them to a temp directory, and loads.
// If the preamble's field names or the sidecar schema change, this fails
// instead of shipping a broken first-contact example.

import Foundation
import Metal
import Testing
@testable import Presets

@Suite("Docs — YOUR_FIRST_PRESET example compiles")
struct DocsExampleCompileTests {

    /// Locate the repo root by walking up from this file (works in-repo;
    /// skips gracefully if the docs tree is absent, e.g. installed-package contexts).
    private static var docURL: URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("docs/presets/YOUR_FIRST_PRESET.md")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private func fencedBlock(_ language: String, in text: String) -> String? {
        guard let start = text.range(of: "```\(language)\n") else { return nil }
        guard let end = text.range(of: "\n```", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    @Test func walkthroughPair_compilesAndLoads() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("No Metal device — skipping")
            return
        }
        guard let docURL = Self.docURL,
              let doc = try? String(contentsOf: docURL, encoding: .utf8) else {
            print("DocsExampleCompileTests: docs tree not present — skipping")
            return
        }
        let metal = try #require(fencedBlock("metal", in: doc), "doc must contain a ```metal block")
        let json = try #require(fencedBlock("json", in: doc), "doc must contain a ```json block")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene-docs-example-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try metal.write(to: tempDir.appendingPathComponent("Halo.metal"), atomically: true, encoding: .utf8)
        try json.write(to: tempDir.appendingPathComponent("Halo.json"), atomically: true, encoding: .utf8)

        let loader = PresetLoader(
            device: device, pixelFormat: .bgra8Unorm_srgb,
            watchDirectory: tempDir, loadBuiltIn: false)

        #expect(loader.presets.count == 1,
                "the walkthrough pair must compile through the real loader")
        #expect(loader.presets.first?.descriptor.name == "Halo")
        #expect(loader.presets.first?.descriptor.audioRoutes.isEmpty == false,
                "the example must model a declared audio_routes manifest")
    }
}
