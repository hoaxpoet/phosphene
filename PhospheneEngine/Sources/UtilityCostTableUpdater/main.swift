// UtilityCostTableUpdater — CLI to update SHADER_CRAFT.md §9.4 performance table.
//
// Reads docs/V4_PERF_RESULTS.json and replaces the sentinel-comment-bounded region
// in SHADER_CRAFT.md §9.4 with a formatted two-column Markdown table.
//
// Usage:
//   swift run --package-path PhospheneEngine UtilityCostTableUpdater \
//     --results docs/V4_PERF_RESULTS.json \
//     --shader-craft docs/SHADER_CRAFT.md
//
// Sentinel comments in SHADER_CRAFT.md:
//   <!-- BEGIN V4 PERF TABLE -->
//   ...table content...
//   <!-- END V4 PERF TABLE -->
//
// The tool replaces everything between (and including) the sentinel lines.

import ArgumentParser
import Foundation

@main
struct UtilityCostTableUpdater: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Update SHADER_CRAFT.md §9.4 performance table from V4_PERF_RESULTS.json."
    )

    @Option(name: .long, help: "Path to docs/V4_PERF_RESULTS.json")
    var results: String = "docs/V4_PERF_RESULTS.json"

    @Option(name: .long, help: "Path to docs/SHADER_CRAFT.md")
    var shaderCraft: String = "docs/SHADER_CRAFT.md"

    @Flag(name: .long, help: "Print generated table without writing to file")
    var dryRun: Bool = false

    mutating func run() throws {
        // Read JSON
        let jsonURL = URL(fileURLWithPath: results)
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        let report = try decoder.decode(PerformanceReport.self, from: jsonData)

        // Build table
        let table = buildTable(report: report)

        // Read SHADER_CRAFT.md
        let mdURL = URL(fileURLWithPath: shaderCraft)
        var content = try String(contentsOf: mdURL, encoding: .utf8)

        // Find sentinel region and replace
        let beginSentinel = "<!-- BEGIN V4 PERF TABLE -->"
        let endSentinel   = "<!-- END V4 PERF TABLE -->"

        guard let beginRange = content.range(of: beginSentinel),
              let endRange   = content.range(of: endSentinel) else {
            print("ERROR: Sentinel comments not found in \(shaderCraft).")
            print("Add these lines to SHADER_CRAFT.md §9.4:")
            print(beginSentinel)
            print(endSentinel)
            throw ExitCode.failure
        }

        let replacement = "\(beginSentinel)\n\(table)\n\(endSentinel)"
        content.replaceSubrange(beginRange.lowerBound...endRange.upperBound, with: replacement)

        if dryRun {
            print(table)
        } else {
            try content.write(to: mdURL, atomically: true, encoding: .utf8)
            print("Updated \(shaderCraft) with \(report.results.count) entries.")
            print("Device: \(report.deviceName) (\(report.deviceTier))")
            print("Generated at: \(report.generatedAt)")
        }
    }
}

// MARK: - Table builder

private func buildTable(report: PerformanceReport) -> String {
    var lines: [String] = []

    lines.append("_Measured on \(report.deviceName) (\(report.deviceTier)). Generated \(report.generatedAt)._")
    lines.append("")
    lines.append("| Function | Category | Tier 1 (estimated) | Tier 2 (measured) | Notes |")
    lines.append("|---|---|---|---|---|")

    let sorted = report.results.sorted {
        $0.category < $1.category || ($0.category == $1.category && $0.function < $1.function)
    }
    for entry in sorted {
        let t2ms  = entry.medianMicroseconds / 1000.0
        let t2str = String(format: "%.2f ms [measured]", t2ms)

        // Tier 1 estimate: ~2.3× slower than Tier 2 (M3→M1 TFLOPS ratio).
        let t1ms  = t2ms * 2.3
        let t1str = String(format: "%.2f ms [estimated]", t1ms)

        lines.append("| `\(entry.function)` | \(entry.category) | \(t1str) | \(t2str) | \(entry.notes) |")
    }

    return lines.joined(separator: "\n")
}

// MARK: - JSON model

struct PerformanceReport: Codable {
    let generatedAt: String
    let deviceName: String
    let deviceTier: String
    let results: [PerformanceEntry]
}

struct PerformanceEntry: Codable {
    let function: String
    let category: String
    let medianMicroseconds: Double
    let minMicroseconds: Double
    let maxMicroseconds: Double
    let notes: String
}
