// MSLNamingTests — mechanizes three silent-failure shader-naming rules (REVIEW.4, 2026-06-11).
//
// All three caused real defects whose only symptom was a preset silently vanishing from the
// catalog (runtime shader-compile failure → PresetLoader drops the preset → only the
// production-count test notices, indirectly):
//   1. Former FA #72 — Swift camelCase field names used in MSL (`f.beatBass` instead of
//      `f.beat_bass`). The banned list is DERIVED from Common.metal's struct fields, so new
//      fields are covered automatically.
//   2. Former DN-35 / FA #44 — MSL type keywords shadowed by variable names (`float half`).
//   3. Former DN-11 — the non-existent `[[thread_index_in_mesh]]` attribute.
//
// The checker functions are pure and unit-tested against known-bad snippets below, so the
// corpus scans provably have teeth (the Skein.4 A/B lesson: an untested gate can't tell a
// fix from a displacement).

import Foundation
import Testing

@Suite("MSL naming lints (former FA #72 / DN-35 / DN-11)")
struct MSLNamingTests {

    // MARK: - Repo access (DocIntegrityTests pattern)

    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }()

    private static var commonMetalURL: URL {
        repoRoot.appendingPathComponent("PhospheneEngine/Sources/Renderer/Shaders/Common.metal")
    }

    /// Every production .metal file under the engine sources.
    private static func metalFiles() -> [URL] {
        let base = repoRoot.appendingPathComponent("PhospheneEngine/Sources")
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension == "metal" { out.append(url) }
        return out
    }

    // MARK: - Checkers (pure)

    /// Snake_case → camelCase ("beat_bass" → "beatBass"). Identity for single-word names.
    static func camelCased(_ snake: String) -> String {
        let parts = snake.split(separator: "_").map(String.init)
        guard parts.count > 1 else { return snake }
        return parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// Multi-word field names declared in the GPU structs of Common.metal (the names whose
    /// camelCase twin is the FA #72 trap). Single-word fields are skipped (no twin).
    static func bannedCamelNames(commonMetal: String) -> Set<String> {
        var banned = Set<String>()
        var inStruct = false
        for rawLine in commonMetal.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("struct ") { inStruct = true; continue }
            if inStruct && line.hasPrefix("};") { inStruct = false; continue }
            guard inStruct, line.hasSuffix(";"), let typeEnd = line.firstIndex(of: " ") else { continue }
            let decl = line[line.index(after: typeEnd)...].dropLast()  // drop ';'
            for field in decl.split(separator: ",") {
                let name = field.trimmingCharacters(in: .whitespaces)
                    .split(separator: "[").first.map(String.init) ?? ""   // strip array suffix
                guard name.contains("_"), !name.hasPrefix("_") else { continue }
                banned.insert(camelCased(name))
            }
        }
        return banned
    }

    /// FA #72: member accesses of banned camelCase names (`.beatBass`).
    static func camelFieldViolations(in text: String, banned: Set<String>) -> [String] {
        guard !banned.isEmpty else { return [] }
        let pattern = #"\.(\#(banned.sorted().joined(separator: "|")))\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// DN-35: MSL scalar/vector type keywords used as variable names (`float half = …`).
    static func typeShadowViolations(in text: String) -> [String] {
        let pattern = #"\b(?:float|half|int|uint|bool|short|ushort|uchar|char)[234]?(?:x[234])?\s+(half|float|int|uint|bool|short|ushort|uchar|char)\b\s*[=;,)]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    // MARK: - Teeth checks (known-bad snippets MUST trip the checkers)

    @Test func checkersCatchKnownBadSnippets() throws {
        let banned = Self.bannedCamelNames(commonMetal: "struct FeatureVector {\n float beat_bass, bass;\n float drums_energy_dev;\n};\n")
        #expect(banned == ["beatBass", "drumsEnergyDev"])
        #expect(!Self.camelFieldViolations(in: "float x = f.beatBass + s.drumsEnergyDev;", banned: banned).isEmpty)
        #expect(Self.camelFieldViolations(in: "float x = f.beat_bass; float beatBassLocal = 1.0;", banned: banned).isEmpty)
        #expect(!Self.typeShadowViolations(in: "float half = 0.5;").isEmpty)
        #expect(!Self.typeShadowViolations(in: "float3 int = v;").isEmpty)
        #expect(Self.typeShadowViolations(in: "float halfWidth = 0.5; half intensity = 1.0h;").isEmpty)
    }

    // MARK: - Corpus scans

    @Test("No Swift camelCase struct-field names in .metal (former FA #72)")
    func noCamelCaseFieldAccessInShaders() throws {
        let common = (try? String(contentsOf: Self.commonMetalURL, encoding: .utf8)) ?? ""
        guard !common.isEmpty else { print("MSLNamingTests: Common.metal not present — skipping"); return }
        let banned = Self.bannedCamelNames(commonMetal: common)
        #expect(banned.count >= 20, "Banned-name derivation imploded (\(banned.count)) — Common.metal struct parse broke")
        for url in Self.metalFiles() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let hits = Self.camelFieldViolations(in: text, banned: banned)
            #expect(hits.isEmpty, "\(url.lastPathComponent): Swift-style field access \(hits) — MSL fields are snake_case; the camelCase twin compiles nowhere and silently drops the preset (former FA #72)")
        }
    }

    @Test("No MSL type-keyword shadowing in .metal (former DN-35 / FA #44)")
    func noTypeShadowingInShaders() throws {
        for url in Self.metalFiles() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let hits = Self.typeShadowViolations(in: text)
            #expect(hits.isEmpty, "\(url.lastPathComponent): variable named after an MSL type \(hits) — silently kills the shader at runtime compile (former DN-35)")
        }
    }

    @Test("No [[thread_index_in_mesh]] attribute (former DN-11 — it does not exist)")
    func noNonexistentMeshAttribute() throws {
        for url in Self.metalFiles() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            #expect(!text.contains("thread_index_in_mesh"),
                    "\(url.lastPathComponent): [[thread_index_in_mesh]] is not a real MSL attribute (former DN-11) — use thread_position_in_grid / the mesh-grid builtins")
        }
    }
}
