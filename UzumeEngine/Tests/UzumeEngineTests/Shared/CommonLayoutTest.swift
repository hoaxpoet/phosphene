// CommonLayoutTest — D-099 layout invariant for buffer(0) / buffer(3) bindings.
//
// Swift `FeatureVector` (224 bytes / 56 floats) and `StemFeatures`
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
        #expect(MemoryLayout<FeatureVector>.size == 224 /* 56 floats = 224 bytes. DYN.1 added spectral_density/_slow (floats 49-50) taking it to 200, which is NOT 16-byte aligned; floats 51-52 were padding that restored it and were then claimed by DYN.1b/DYN.2. FTR.24 adds spectral_level_rise (float 53) and floats 54-56 are the padding that restores the alignment every preset depends on at buffer(0). */)
        #expect(MemoryLayout<StemFeatures>.size == 256)
    }

    // MARK: - MSL parity (DYN.2 regression)

    /// Locates the repo root from this file's path so the test can read the two MSL
    /// declaration sites directly.
    ///
    /// **Ascend to an anchor, not to a name and not by a count (FTR.6, hardened QG.6).**
    /// The original form walked up until it found a directory literally named `phosphene` —
    /// which in a git worktree at `phosphene/.claude/worktrees/<name>/` sails straight past
    /// the worktree and lands on the PRIMARY checkout. The gate then read the worktree's
    /// Swift struct and the primary's `.metal`, so an MSL edit made in a worktree was
    /// invisible to it while an untouched primary reported a phantom mismatch. Both
    /// directions are silent, and FTR.6 hit the second.
    ///
    /// FTR.6 replaced the name search with a fixed component count, which fixes the
    /// worktree case but re-breaks the moment this file moves — and a wrong root reads as
    /// "sources unreadable", which the parity test used to treat as a *pass*. Ascending to
    /// the nearest ancestor containing `PhospheneEngine/Package.swift` is self-validating:
    /// a worktree root matches before the primary ever comes into range, and the result is
    /// either provably the enclosing checkout or `nil`.
    ///
    /// `nil` means this is not a source checkout (a bundled test product run outside the
    /// tree) — the ONLY legitimate reason the MSL sources are unreadable. Same
    /// arm-the-gate-or-skip-cleanly distinction `DocIntegrityTests.docsPresent` draws.
    private static let repoRoot: URL? = {
        var url = URL(fileURLWithPath: #filePath)
        // file → Shared → PhospheneEngineTests → Tests → PhospheneEngine → root is 5,
        // but never rely on that: search, and bound the search so it cannot run away.
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            guard url.pathComponents.count > 1 else { return nil }
            let anchor = url.appendingPathComponent("PhospheneEngine/Package.swift")
            if FileManager.default.fileExists(atPath: anchor.path) { return url }
        }
        return nil
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
    ///
    /// **An unreadable source is a FAILURE here, not a skip (QG.6).** The gate previously
    /// printed and returned green whenever either file could not be read, which made a
    /// wrong `repoRoot` indistinguishable from a pass — the same silent-success shape the
    /// gate exists to prevent, one level up. The only legitimate absence is "not a source
    /// checkout", and `repoRoot` now decides that explicitly by finding the enclosing
    /// package or returning `nil`. Past that point the files must exist.
    @Test func mslFeatureVector_matchesSwiftSizeAndAgreesAcrossBothSites() throws {
        guard let root = Self.repoRoot else {
            print("CommonLayoutTest: not a source checkout — skipping MSL parity")
            return
        }
        // The FTR.6 bug in one assertion: the root must enclose THIS file. A root that
        // resolves outside our own tree is how the gate came to compare two checkouts.
        #expect(
            URL(fileURLWithPath: #filePath).path.hasPrefix(root.path + "/"),
            "repoRoot \(root.path) does not contain \(#filePath) — the gate would read another checkout"
        )

        let commonURL = root
            .appendingPathComponent("PhospheneEngine/Sources/Renderer/Shaders/Common.metal")
        let preambleURL = root
            .appendingPathComponent("PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift")
        let common = try #require(
            try? String(contentsOf: commonURL, encoding: .utf8),
            "Common.metal unreadable at \(commonURL.path). This is a source checkout (\(root.path) has PhospheneEngine/Package.swift), so the GPU contract is unverified — never a pass."
        )
        let preamble = try #require(
            try? String(contentsOf: preambleURL, encoding: .utf8),
            "PresetLoader+Preamble.swift unreadable at \(preambleURL.path). This is a source checkout, so the GPU contract is unverified — never a pass."
        )
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
