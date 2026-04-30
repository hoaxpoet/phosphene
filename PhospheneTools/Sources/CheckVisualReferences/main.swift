// CheckVisualReferences — Lint check for docs/VISUAL_REFERENCES/.
//
// Validates that every preset registered in the Presets shader directory has a
// corresponding VISUAL_REFERENCES folder with a populated README, and that all
// image filenames follow the _NAMING_CONVENTION.md pattern.
//
// Usage (from project root):
//   swift run --package-path PhospheneTools CheckVisualReferences
//   swift run --package-path PhospheneTools CheckVisualReferences --strict
//   swift run --package-path PhospheneTools CheckVisualReferences --project-root /path/to/project
//
// Default mode: prints warnings but exits 0 (fail-soft, for the intermediate
// curation state where folders exist but images are not yet committed).
// --strict mode: exits non-zero on any warning (flip to this in V.6 once
// Matt's curation is complete).

import ArgumentParser
import Foundation

// MARK: - Entry point

@main
struct CheckVisualReferences: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Lint check for docs/VISUAL_REFERENCES/ completeness and naming convention."
    )

    @Option(name: .long, help: "Path to project root (default: current directory)")
    var projectRoot: String = "."

    @Flag(name: .long, help: "Exit non-zero on any warning (enable after curation is complete)")
    var strict: Bool = false

    mutating func run() throws {
        let root = URL(fileURLWithPath: projectRoot).standardizedFileURL
        let refsDir = root.appendingPathComponent("docs/VISUAL_REFERENCES")
        let shadersDir = root.appendingPathComponent(
            "PhospheneEngine/Sources/Presets/Shaders"
        )

        var warnings: [String] = []
        var errors: [String] = []

        // Step 1: Discover registered presets from Shaders/ (mirrors PresetLoader's flat scan).
        let registeredPresets = discoverPresets(in: shadersDir, errors: &errors)
        if registeredPresets.isEmpty && errors.isEmpty {
            errors.append("No preset .metal files found in \(shadersDir.path). Is --project-root correct?")
        }

        // Step 2: Check docs/VISUAL_REFERENCES/ exists.
        guard FileManager.default.fileExists(atPath: refsDir.path) else {
            errors.append("docs/VISUAL_REFERENCES/ not found. Run V.5 scaffolding first.")
            report(warnings: warnings, errors: errors, strict: strict)
            return
        }

        // Step 3: Validate each preset has a folder + README with required sections.
        for preset in registeredPresets {
            let folderName = camelToSnake(preset)
            let folderURL = refsDir.appendingPathComponent(folderName)
            let readmeURL = folderURL.appendingPathComponent("README.md")

            guard FileManager.default.fileExists(atPath: folderURL.path) else {
                warnings.append("[\(folderName)] folder missing — expected docs/VISUAL_REFERENCES/\(folderName)/")
                continue
            }

            guard FileManager.default.fileExists(atPath: readmeURL.path) else {
                warnings.append("[\(folderName)] README.md missing")
                continue
            }

            let readmeIssues = validateReadme(at: readmeURL, presetFolder: folderName)
            warnings.append(contentsOf: readmeIssues)

            // Step 4: Validate image filenames in this folder.
            let imageIssues = validateImages(in: folderURL, readmeURL: readmeURL, presetFolder: folderName)
            warnings.append(contentsOf: imageIssues)
        }

        // Step 5: Check phase_md/ has only its README (no stray top-level images).
        let phaseMDDir = refsDir.appendingPathComponent("phase_md")
        if FileManager.default.fileExists(atPath: phaseMDDir.path) {
            let strayIssues = checkPhaseMDStrayImages(in: phaseMDDir)
            warnings.append(contentsOf: strayIssues)
        }

        report(warnings: warnings, errors: errors, strict: strict)
    }
}

// MARK: - Preset discovery

/// Scans Shaders/ directory (flat, matching PresetLoader behaviour) for .metal files,
/// excludes utility files, and returns the base names.
private func discoverPresets(in shadersDir: URL, errors: inout [String]) -> [String] {
    let utilityFileNames: Set<String> = ["ShaderUtilities.metal"]
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(
        at: shadersDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: .skipsHiddenFiles
    ) else {
        errors.append("Could not read \(shadersDir.path)")
        return []
    }

    return contents
        .filter { $0.pathExtension == "metal" }
        .filter { !utilityFileNames.contains($0.lastPathComponent) }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()
}

// MARK: - CamelCase → snake_case

/// Converts CamelCase preset names to the snake_case folder names used in VISUAL_REFERENCES/.
/// Examples: "VolumetricLithograph" → "volumetric_lithograph", "GlassBrutalist" → "glass_brutalist"
private func camelToSnake(_ input: String) -> String {
    // Insert underscore before each uppercase letter that follows a lowercase letter.
    let result = input.replacingOccurrences(
        of: "([a-z0-9])([A-Z])",
        with: "$1_$2",
        options: .regularExpression
    )
    return result.lowercased()
}

// MARK: - README validation

private let requiredFullRubricSections = [
    "## Reference images",
    "## Mandatory traits",
    "## Expected traits",
    "## Strongly preferred traits",
    "## Anti-references",
    "## Audio routing notes",
    "## Provenance",
]

private let requiredLightweightSections = [
    "## Reference images",
    "## Stylization contract",
    "## Anti-references",
    "## Audio routing notes",
    "## Provenance",
]

private func validateReadme(at url: URL, presetFolder: String) -> [String] {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        return ["[\(presetFolder)] README.md could not be read"]
    }

    var issues: [String] = []

    // Determine which section set to check based on whether "lightweight" appears in the header.
    let isLightweight = content.contains("**Rubric:** lightweight")
    let required = isLightweight ? requiredLightweightSections : requiredFullRubricSections

    for section in required where !content.contains(section) {
        issues.append("[\(presetFolder)] README.md missing section: \(section)")
    }

    return issues
}

// MARK: - Image filename validation

// swiftlint:disable:next force_try
private let imageNameRegex = try! NSRegularExpression(
    pattern: #"^[0-9]{2}_(macro|meso|micro|specular|atmosphere|lighting|palette|anti)_[a-z0-9_]+\.(jpg|png)$"#
)

/// Validates image filenames in a preset folder and checks that the README's
/// reference-image table links to files that actually exist.
private func validateImages(in folderURL: URL, readmeURL: URL, presetFolder: String) -> [String] {
    let fm = FileManager.default
    var issues: [String] = []

    guard let contents = try? fm.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: nil,
        options: .skipsHiddenFiles
    ) else {
        return ["[\(presetFolder)] could not list folder contents"]
    }

    let imageFiles = contents.filter {
        let ext = $0.pathExtension.lowercased()
        return ext == "jpg" || ext == "png"
    }

    // Rule 3: every image must match the naming regex.
    for imageURL in imageFiles {
        let filename = imageURL.lastPathComponent
        let range = NSRange(filename.startIndex..., in: filename)
        if imageNameRegex.firstMatch(in: filename, range: range) == nil {
            issues.append(
                "[\(presetFolder)] image filename '\(filename)' does not match " +
                "NN_<scale>_<descriptor>.<ext> — see _NAMING_CONVENTION.md"
            )
        }
    }

    // Warn if the folder has no images yet (expected during curation phase).
    if imageFiles.isEmpty {
        issues.append("[\(presetFolder)] no reference images — Matt needs to curate 3–5 images")
    }

    // Rule 4: README image table links must resolve to existing files.
    if let readmeContent = try? String(contentsOf: readmeURL, encoding: .utf8) {
        let linkedFiles = extractImageTableLinks(from: readmeContent)
        for linkedFile in linkedFiles {
            // Skip placeholder entries like `01_macro_<...>.jpg`
            guard !linkedFile.contains("<") else { continue }
            let fileURL = folderURL.appendingPathComponent(linkedFile)
            if !fm.fileExists(atPath: fileURL.path) {
                issues.append("[\(presetFolder)] README references '\(linkedFile)' but file not found")
            }
        }
    }

    return issues
}

/// Extracts filenames from the reference image table in a README.
/// Looks for backtick-quoted values in table rows that end in .jpg or .png.
private func extractImageTableLinks(from readme: String) -> [String] {
    var results: [String] = []
    let pattern = "`([^`]+\\.(jpg|png))`"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let nsString = readme as NSString
    let matches = regex.matches(in: readme, range: NSRange(location: 0, length: nsString.length))
    for match in matches where match.numberOfRanges >= 2 {
        let range = match.range(at: 1)
        if range.location != NSNotFound {
            results.append(nsString.substring(with: range))
        }
    }
    return results
}

// MARK: - phase_md/ stray image check

private func checkPhaseMDStrayImages(in phaseMDDir: URL) -> [String] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
        at: phaseMDDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: .skipsHiddenFiles
    ) else {
        return []
    }

    var issues: [String] = []
    for item in contents where item.pathExtension.lowercased() == "jpg" || item.pathExtension.lowercased() == "png" {
        // phase_md/ should contain only README.md and preset subfolders — no top-level images.
        issues.append("[phase_md] stray image '\(item.lastPathComponent)'")
    }
    return issues
}

// MARK: - Reporting

private func report(warnings: [String], errors: [String], strict: Bool) {
    let total = warnings.count + errors.count

    if errors.isEmpty && warnings.isEmpty {
        print("✓ CheckVisualReferences: all checks passed.")
        return
    }

    for error in errors {
        print("error: \(error)")
    }
    for warning in warnings {
        print("warning: \(warning)")
    }

    print("")
    if errors.isEmpty {
        let mode = strict ? "strict" : "fail-soft"
        print("CheckVisualReferences: \(warnings.count) warning(s), 0 error(s) [\(mode) mode]")
        print("Run with --strict to fail the build. Flip default to --strict in V.6 once curation is complete.")
    } else {
        print("CheckVisualReferences: \(warnings.count) warning(s), \(errors.count) error(s)")
    }

    if strict && total > 0 {
        Foundation.exit(1)
    }
}
