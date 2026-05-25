// ColdStartVerifierCommand+AccentWindow — BSAudit.3.validate.1 runner wiring.
//
// Extension on `ColdStartVerifierCommand` that hosts the
// `--accent-window-pass-rate` runner method. Lives in its own file to keep
// the main command file under SwiftLint's file-length cap and to match the
// per-mode-file convention established by `+PathA`.

import Foundation
import Session

extension ColdStartVerifierCommand {

    /// BSAudit.3.validate.1 — accent-window pass-rate scoring against Beat This!.
    func runAccentWindowPassRate(
        sessionURL: URL,
        artifacts: SessionArtifacts,
        rawTap: RawTapAnalysis,
        analyzer: DefaultBeatGridAnalyzer
    ) throws {
        let config = AccentWindowConfig(
            firstWindowS: firstWindowS,
            windowStartS: windowStartS,
            acceptMs: acceptMs,
            accentThreshold: accentThreshold,
            perTrackPassRate: perTrackPassRate,
            degradedConfThreshold: degradedConfThreshold)
        print("ColdStartVerifier: accent-window-pass-rate — "
            + "±\(Int(config.acceptMs.rounded())) ms accept, "
            + "threshold \(String(format: "%.2f", config.accentThreshold)) …")
        let analysis = AccentWindowPassRate.run(
            tracks: artifacts.tracks,
            config: config,
            rawTap: rawTap,
            rawTapStartWallclockS: artifacts.rawTapStartWallclockS,
            analyzer: analyzer)
        let md = AccentWindowReport.render(
            sessionURL: sessionURL, analysis: analysis, config: config)
        let outURL = out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? sessionURL.appendingPathComponent("cold_start_accent_window.md")
        try md.write(to: outURL, atomically: true, encoding: .utf8)
        print("")
        print(analysis.consoleSummary(config: config))
        print("ColdStartVerifier: accent-window report → \(outURL.path)")
    }
}
