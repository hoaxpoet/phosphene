// CommonLayoutTest — D-099 layout invariant for buffer(0) / buffer(3) bindings.
//
// Swift `FeatureVector` (192 bytes / 48 floats) and `StemFeatures`
// (256 bytes / 64 floats) are bound directly to MSL preset preambles
// (PresetLoader+Preamble.swift) and to the engine library Common.metal.
// If either Swift struct ever shrinks, every shader that reads past the
// smaller boundary over-reads its bound buffer — silently on release
// builds, with undefined values feeding the rendered frame.
//
// This test fails fast at CI time before MSL ever sees the regression. It
// is the Swift-side companion to D-099; locking on the engine MSL side is
// not portable in MSL, so the gate lives here.

import Testing
import Foundation
@testable import Shared

// MARK: - CommonLayoutTest

struct CommonLayoutTest {

    /// Locks Swift `FeatureVector` and `StemFeatures` sizes to the values
    /// Common.metal's MSL structs were extended to in D-099. Failing this
    /// test is the canary that the buffer(2) / buffer(3) layout contract
    /// has drifted between Swift and MSL.
    @Test func featureVector_stemFeatures_layouts_locked() {
        #expect(MemoryLayout<FeatureVector>.size == 208 /* 52 floats = 208 bytes. DYN.1 added spectral_density/_slow (floats 49-50) taking it to 200, which is NOT 16-byte aligned; floats 51-52 are padding that restores the GPU-constant alignment every preset depends on at buffer(0). */)
        #expect(MemoryLayout<StemFeatures>.size == 256)
    }

    // MARK: - MSL parity (DYN.2 regression)

    /// Locates the repo root from this file's path so the test can read the two MSL
    /// declaration sites directly.
    ///
    /// **Relative ascent, not a name search.** Walking up to a directory literally named
    /// `phosphene` sails past a git worktree at `phosphene/.claude/worktrees/<name>/` and
    /// lands on the PRIMARY checkout, so the gate read this tree's Swift struct against
    /// another tree's `.metal`. Both directions are silent: a worktree that legitimately
    /// changes the layout in both places can go green on a real mismatch, and an untouched
    /// worktree can report a phantom one the moment the primary's checkout moves. Count
    /// components instead — this file sits a fixed depth below the repo root, in a
    /// worktree or out of it.
    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // file → Shared → PhospheneEngineTests → Tests → PhospheneEngine → root
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    /// Extract the `float` field names of `struct FeatureVector`, in declaration order.
    private static func mslFields(of source: String) -> [String] {
        guard let start = source.range(of: "struct FeatureVector {"),
              let end = source.range(of: "};", range: start.upperBound..<source.endIndex)
        else { return [] }
        return source[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            // Strip trailing `//` comments FIRST — several declarations carry them, and a
            // parser that drops those lines invents a divergence that is not there.
            .map { line -> String in
                let code = line.components(separatedBy: "//").first ?? String(line)
                return code.trimmingCharacters(in: .whitespaces)
            }
            .filter { $0.hasPrefix("float ") && $0.hasSuffix(";") }
            .flatMap { line -> [String] in
                line.dropFirst("float ".count).dropLast()
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            .filter { !$0.isEmpty }
    }

    /// **THE GATE THIS FILE WAS MISSING, and it shipped a broken build to `main`.**
    ///
    /// DYN.2 added a field by claiming Swift's `_pad52` (net zero bytes) while *inserting*
    /// a field on the MSL side without removing its pad. Swift stayed 208 bytes so the
    /// assertion above stayed green; the shader struct became 212, and every draw died at
    /// runtime: *"argument features[0] from Buffer(0) … has space for 208 bytes, but
    /// argument has a length(212)."* The same edit also placed the new field BEFORE
    /// `spectral_surge` in MSL and AFTER it in Swift — so even at a matching size the two
    /// fields would have silently swapped, which a byte-count check alone cannot see.
    ///
    /// Order is the contract, not just the count.
    @Test func mslFeatureVector_matchesSwiftSizeAndAgreesAcrossBothSites() throws {
        let commonURL = Self.repoRoot
            .appendingPathComponent("PhospheneEngine/Sources/Renderer/Shaders/Common.metal")
        let preambleURL = Self.repoRoot
            .appendingPathComponent("PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift")
        guard let common = try? String(contentsOf: commonURL, encoding: .utf8),
              let preamble = try? String(contentsOf: preambleURL, encoding: .utf8) else {
            print("CommonLayoutTest: MSL sources not reachable — skipping")
            return
        }
        let commonFields = Self.mslFields(of: common)
        let preambleFields = Self.mslFields(of: preamble)

        #expect(commonFields.count > 40, "Common.metal FeatureVector parse imploded")
        #expect(commonFields.count * 4 == MemoryLayout<FeatureVector>.size, """
            Common.metal declares \(commonFields.count) floats = \(commonFields.count * 4) bytes, \
            but Swift FeatureVector is \(MemoryLayout<FeatureVector>.size). Every draw binding \
            buffer(0) fails Metal validation at runtime with exactly this delta.
            """)
        #expect(commonFields == preambleFields, """
            The two MSL declaration sites disagree. Runtime-compiled presets use the \
            PresetLoader preamble and engine shaders use Common.metal, so a divergence \
            silently corrupts one of them. First difference: \
            \(zip(commonFields, preambleFields).first { $0 != $1 }.map { "\($0) vs \($1)" } ?? "length")
            """)
    }
}
