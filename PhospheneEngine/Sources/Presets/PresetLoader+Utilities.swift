// PresetLoader+Utilities — V.1 shader utility tree loading (Noise + PBR).
//
// Concatenates Metal utility files in dependency-topological order before the
// main shader preamble. See PresetLoader+Preamble for the full load order.

import Foundation
import os.log

private let utilitiesLogger = Logger(subsystem: "com.phosphene.presets", category: "Utilities")

// MARK: - Utility File Loading

extension PresetLoader {

    // Explicit concatenation order for the Noise utility subtree.
    // Order is dependency-topological: Hash → Perlin → Simplex → FBM →
    // RidgedMultifractal → Worley (worley_fbm needs fbm8) → DomainWarp →
    // Curl → BlueNoise. Any file not listed here is appended alphabetically.
    static let noiseLoadOrder = [
        "Hash.metal", "Perlin.metal", "Simplex.metal", "FBM.metal",
        "RidgedMultifractal.metal", "Worley.metal", "DomainWarp.metal",
        "Curl.metal", "BlueNoise.metal"
    ]

    // Explicit order for the PBR utility subtree.
    // Fresnel and NormalMapping first (other PBR files depend on them).
    static let pbrLoadOrder = [
        "Fresnel.metal", "NormalMapping.metal", "BRDF.metal", "Thin.metal",
        "DetailNormals.metal", "Triplanar.metal", "POM.metal", "SSS.metal",
        "Fiber.metal"
    ]

    // V.2 — Geometry utility subtree (Part A).
    // SDFPrimitives first (Boolean + Modifiers + Displacement depend on sd_* names).
    // RayMarch and HexTile are independent leaf utilities.
    static let geometryLoadOrder = [
        "SDFPrimitives.metal", "SDFBoolean.metal", "SDFModifiers.metal",
        "SDFDisplacement.metal", "RayMarch.metal", "HexTile.metal"
    ]

    // V.2 — Volume utility subtree (Part B).
    // HenyeyGreenstein has no deps; ParticipatingMedia + Clouds depend on HG.
    // Clouds also depends on fbm8 (Noise tree, loaded before Volume in preamble).
    static let volumeLoadOrder = [
        "HenyeyGreenstein.metal", "ParticipatingMedia.metal", "Clouds.metal",
        "LightShafts.metal", "Caustics.metal"
    ]

    // V.2 — Texture utility subtree (Part C).
    // Voronoi first (Caustics in Volume references it conceptually; Procedural
    // uses Voronoi for marble veins). ReactionDiffusion, FlowMaps, Grunge are
    // independent. Procedural depends on Voronoi (voronoi_2d).
    static let textureLoadOrder = [
        "Voronoi.metal", "ReactionDiffusion.metal", "FlowMaps.metal",
        "Procedural.metal", "Grunge.metal"
    ]

    /// Concatenate all Metal utility files from a bundle subdirectory.
    ///
    /// Files are ordered using `priorityOrder`: listed files come first in that
    /// order; any unlisted files are appended alphabetically (forward-compatible).
    static func loadUtilityDirectory(
        _ subdirectory: String,
        priorityOrder: [String],
        from shadersURL: URL
    ) -> String {
        let dirURL = shadersURL.appendingPathComponent(subdirectory)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            utilitiesLogger.warning("Utility directory not found: \(subdirectory)")
            return ""
        }

        let metalFiles = contents.filter { $0.pathExtension == "metal" }
        let nameToURL = Dictionary(uniqueKeysWithValues: metalFiles.map { ($0.lastPathComponent, $0) })

        // Build ordered list: priority names first, then remaining alphabetically.
        var ordered: [URL] = []
        for name in priorityOrder {
            if let url = nameToURL[name] { ordered.append(url) }
        }
        let remaining = metalFiles
            .filter { !priorityOrder.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        ordered.append(contentsOf: remaining)

        var combined = ""
        for url in ordered {
            if let src = try? String(contentsOf: url, encoding: .utf8) {
                combined += "\n// ─── \(url.lastPathComponent) ───\n" + src + "\n"
                utilitiesLogger.debug("Loaded utility: \(url.lastPathComponent)")
            } else {
                utilitiesLogger.warning("Could not read utility file: \(url.lastPathComponent)")
            }
        }

        utilitiesLogger.info(
            "Loaded \(ordered.count) utility file(s) from \(subdirectory) (\(combined.count) chars)")
        return combined
    }
}
