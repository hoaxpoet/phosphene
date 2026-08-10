// PresetSidecarKeyGateTests — an unrecognised sidecar key is a failure, not a silent no-op.
//
// `PresetDescriptor` is `Codable`, and synthesized `Codable` **ignores keys it does not
// know**. A sidecar can therefore carry a field that looks authoritative, reads as live to
// anyone opening the file, and is never decoded by anything.
//
// This is not hypothetical. D-120 added `concept_tags` + `motion_paradigm` to the sidecar
// schema; D-123 reverted them the next day and the revert was clean — the CA.4 audit's
// 2026-05-20 grep correctly reported zero residue. Both fields nonetheless reappeared in
// two sidecars created *months later* (CymaticResonance.json 2026-07-22, Meniscus.json
// 2026-08-03), because the design docs those presets were authored from still prescribed
// them. Nothing rejected the keys, so nothing noticed until MD.0 went looking. A clean
// grep is a statement about a moment; this gate is a statement about every commit.
//
// The same shape bit the provenance block one level down: `Witchlight.json` carried a
// bespoke `sha256_subject` key that no schema mentioned and no reader consumed.
//
// The gate does not decide what an unknown key *should* be — it forces the decision to be
// explicit. Decode it, allow-list it here with a reason, or delete it.

import Testing
import Foundation
@testable import Presets

// MARK: - PresetSidecarKeyGateTests

struct PresetSidecarKeyGateTests {

    // MARK: - Repo location

    /// The enclosing checkout, found by ascending to the nearest ancestor containing
    /// `PhospheneEngine/Package.swift`; `nil` when this is not a source checkout.
    ///
    /// Same anchor-search as `CommonLayoutTest` (QG.6) and for the same reason: a name
    /// search walks past a git worktree onto the primary checkout, and a fixed component
    /// count breaks silently when a file moves. Duplicated rather than shared because
    /// hoisting a helper would mean touching three gates at once; worth unifying the day
    /// a fourth appears.
    private static let repoRoot: URL? = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            guard url.pathComponents.count > 1 else { return nil }
            let anchor = url.appendingPathComponent("PhospheneEngine/Package.swift")
            if FileManager.default.fileExists(atPath: anchor.path) { return url }
        }
        return nil
    }()

    // MARK: - Known keys

    /// Top-level keys that are deliberately present and deliberately NOT decoded.
    /// Every entry needs a reason; an entry without one is how `concept_tags` would
    /// have survived this gate.
    private static let documentationOnlyKeys: [String: String] = [
        "inspired_by": """
            Milkdrop provenance block (D-111 as amended, schema in D-215 §13.3). \
            Documentation-only by decision: `PresetDescriptor` declares no coding key for \
            it and no engine path reads it. Whether it SHOULD be decoded is an open \
            carry-forward on D-215, deliberately not settled by this gate.
            """,
        "lumen_mosaic": """
            LM.2 tuning mirror on LumenMosaic.json. The operative values are Swift \
            constants in LumenPatternEngine.swift; the block restates them for readers. \
            The sync is MANUAL — LumenPatternEngine.swift:393 documents the obligation in \
            prose ("LM.2 keeps the value matched to LumenMosaic.json#lumen_mosaic.\
            ambient_floor_intensity = 0.04") with no mechanism behind it, so the two can \
            drift without anything failing.
            """
    ]

    /// Keys prefixed this way are inline commentary for a human reading the JSON
    /// (`_comment_audio_routes`, `_comment_scene_fog`, …). JSON has no comment syntax;
    /// this is the tree's convention for one.
    private static let commentKeyPrefix = "_comment_"

    /// The `inspired_by` union schema (D-215 §13.3). `sha256` is omitted where no hash was
    /// taken at authoring, so presence is optional — but an unlisted sub-key is not.
    private static let inspiredByKeys: Set<String> = [
        "milkdrop_filename", "original_artist", "pack", "source_form", "sha256"
    ]

    // MARK: - Decoded-key extraction

    /// The wire names `PresetDescriptor` actually decodes, parsed from its `CodingKeys`
    /// declaration.
    ///
    /// Parsed from source rather than hard-coded so the gate cannot go stale the moment
    /// someone adds a field — the same reason `CommonLayoutTest` parses `Common.metal`
    /// instead of restating the MSL layout. A hard-coded copy would need updating in
    /// lockstep with the type, and the failure mode of forgetting is this gate silently
    /// rejecting a legitimate new key.
    static func decodedKeys(from source: String) -> Set<String> {
        // PresetDescriptor's own block is the one declaring the core fields; nested types
        // (Marks, Stages, ThinFilm) each carry their own CodingKeys in the same file.
        let blocks = source.components(separatedBy: "enum CodingKeys: String, CodingKey {").dropFirst()
        guard let block = blocks.first(where: { $0.contains("case name, family, duration") }),
              let end = block.range(of: "\n    }")
        else { return [] }

        var keys: Set<String> = []
        for rawLine in block[block.startIndex..<end.lowerBound].split(separator: "\n") {
            let line = (rawLine.components(separatedBy: "//").first ?? String(rawLine))
                .trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("case ") else { continue }
            for part in line.dropFirst("case ".count).split(separator: ",") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                guard !piece.isEmpty else { continue }
                // `case beatSource = "beat_source"` → the wire name is the raw value;
                // `case decay` → the wire name is the case name.
                if let eq = piece.range(of: "=") {
                    keys.insert(piece[eq.upperBound...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                } else {
                    keys.insert(piece)
                }
            }
        }
        return keys
    }

    // MARK: - Gate

    /// **Every top-level sidecar key is decoded, or explicitly allow-listed with a reason.**
    ///
    /// The failure this prevents: a key that reads as configuration, is authored in good
    /// faith from a design doc, and does nothing.
    @Test func everySidecarKeyIsDecodedOrDocumented() throws {
        guard let root = Self.repoRoot else {
            print("PresetSidecarKeyGateTests: not a source checkout — skipping")
            return
        }
        let shaders = root.appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders")
        let descriptorURL = root.appendingPathComponent("PhospheneEngine/Sources/Presets/PresetDescriptor.swift")

        let descriptorSource = try #require(
            try? String(contentsOf: descriptorURL, encoding: .utf8),
            "PresetDescriptor.swift unreadable at \(descriptorURL.path). This is a source checkout, so the sidecar schema is unverified — never a pass."
        )
        let decoded = Self.decodedKeys(from: descriptorSource)
        #expect(decoded.count > 40, "CodingKeys parse imploded — got \(decoded.count) keys, expected the full PresetDescriptor surface")
        #expect(decoded.contains("audio_routes") && decoded.contains("family") && decoded.contains("certified"),
                "CodingKeys parse looks wrong — known wire names missing from \(decoded.sorted())")

        let sidecars = try #require(
            try? FileManager.default.contentsOfDirectory(at: shaders, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted(by: { $0.path < $1.path }),
            "Shaders directory unreadable at \(shaders.path) — never a pass."
        )
        #expect(sidecars.count > 20, "Only \(sidecars.count) sidecars found; the gate is not seeing the catalog")

        var offences: [String] = []
        for url in sidecars {
            let data = try #require(try? Data(contentsOf: url), "\(url.lastPathComponent) unreadable")
            let object = try #require(
                try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                "\(url.lastPathComponent) is not a JSON object"
            )
            for key in object.keys.sorted() {
                if decoded.contains(key) { continue }
                if Self.documentationOnlyKeys[key] != nil { continue }
                if key.hasPrefix(Self.commentKeyPrefix) { continue }
                offences.append("\(url.lastPathComponent): \"\(key)\"")
            }
        }

        #expect(offences.isEmpty, """
            Unrecognised top-level key(s) in preset sidecars:

            \(offences.joined(separator: "\n            "))

            `PresetDescriptor` does not decode these, so they are inert — they read as \
            configuration and change nothing. This is the D-120 failure exactly: \
            `concept_tags` / `motion_paradigm` were reverted by D-123 and still reappeared \
            in two sidecars authored months later from stale design docs.

            Pick one, deliberately:
              • decode it — add a case to PresetDescriptor.CodingKeys and read it somewhere;
              • document it — add it to `documentationOnlyKeys` above WITH a reason it is
                not decoded and what keeps it honest;
              • delete it — it was never doing anything.
            """)
    }

    /// **The `inspired_by` provenance block matches the D-215 §13.3 union schema.**
    ///
    /// `Witchlight.json` carried a bespoke `sha256_subject` explaining what its hash
    /// covered — the right instinct, the wrong mechanism: an ad-hoc key no schema knew
    /// about. MD.0 folded its meaning into `source_form`. This keeps the block from
    /// re-growing private vocabulary one preset at a time.
    @Test func inspiredByBlocksMatchTheUnionSchema() throws {
        guard let root = Self.repoRoot else {
            print("PresetSidecarKeyGateTests: not a source checkout — skipping")
            return
        }
        let shaders = root.appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders")
        let sidecars = try #require(
            try? FileManager.default.contentsOfDirectory(at: shaders, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted(by: { $0.path < $1.path }),
            "Shaders directory unreadable at \(shaders.path) — never a pass."
        )

        var offences: [String] = []
        var seen = 0
        for url in sidecars {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let block = object["inspired_by"] as? [String: Any]
            else { continue }
            seen += 1
            for key in block.keys.sorted() where !Self.inspiredByKeys.contains(key) {
                offences.append("\(url.lastPathComponent): inspired_by.\"\(key)\"")
            }
            // `sha256` is optional (omitted where no hash was taken); the rest are not.
            for required in ["milkdrop_filename", "original_artist", "pack", "source_form"]
            where block[required] == nil {
                offences.append("\(url.lastPathComponent): inspired_by is missing \"\(required)\"")
            }
        }

        #expect(seen > 0, "No inspired_by blocks found — the gate is not seeing the uplifts")
        #expect(offences.isEmpty, """
            `inspired_by` deviates from the D-215 §13.3 union schema:

            \(offences.joined(separator: "\n            "))

            Schema: milkdrop_filename, original_artist, pack, source_form, and sha256 \
            (omitted where no hash was taken at authoring, with source_form saying why). \
            `sha256` and `source_form` are read together — a bare hash is ambiguous about \
            what was hashed, which is the state DragonBloom.json was in before MD.0.
            """)
    }
}
