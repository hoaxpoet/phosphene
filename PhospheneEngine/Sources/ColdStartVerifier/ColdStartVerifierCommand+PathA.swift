// ColdStartVerifierCommand+PathA — BSAudit.2 runner wiring.
//
// Extension on `ColdStartVerifierCommand` that hosts the Path A.1 (position
// sweep) and Path A.2 (cross-capture) runner methods. Lives in its own file
// to keep the main command file under SwiftLint's file-length cap.

import ArgumentParser
import Foundation
import Metal
import Session

extension ColdStartVerifierCommand {

    /// BSAudit.2 Path A.1 — within-capture Beat This! position-sensitivity sweep.
    func runPositionSweep(
        sessionURL: URL,
        artifacts: SessionArtifacts,
        rawTap: RawTapAnalysis,
        analyzer: DefaultBeatGridAnalyzer
    ) throws {
        let slice = String(format: "%.0f", sliceDurationS)
        let stride = String(format: "%.0f", positionStrideS)
        print("ColdStartVerifier: position-sweep — \(slice) s slice, "
            + "\(stride) s stride …")
        let config = PositionSweep.Config(
            sliceDurationS: sliceDurationS,
            positionStrideS: positionStrideS)
        let results = PositionSweep.run(
            tracks: artifacts.tracks,
            rawTap: rawTap,
            rawTapStartWallclockS: artifacts.rawTapStartWallclockS,
            analyzer: analyzer,
            config: config)
        let md = PositionSweep.report(
            session: sessionURL,
            rawTap: rawTap,
            results: results,
            config: config)
        let outURL = resolveOutURL(
            reference: sessionURL,
            fallback: "cold_start_position_sweep.md")
        try md.write(to: outURL, atomically: true, encoding: .utf8)
        print("")
        print(PositionSweep.consoleSummary(results))
        print("ColdStartVerifier: position-sweep report → \(outURL.path)")
    }

    /// BSAudit.2 Path A.2 — cross-capture Beat This! reproducibility.
    /// Takes a comma-separated `--sessions` list (first = reference).
    func runCrossCapture() throws {
        let inputs = try loadCrossCaptureSessions()
        let slice = String(format: "%.0f", sliceDurationS)
        let posStart = String(format: "%.0f", crossCaptureStartS)
        print("ColdStartVerifier: cross-capture — \(inputs.count) sessions, "
            + "\(slice) s slice @ +\(posStart) s …")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VerifierError.noMetalDevice
        }
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let config = CrossCapture.Config(
            sliceDurationS: sliceDurationS,
            positionStartS: crossCaptureStartS)
        let results = CrossCapture.run(
            sessions: inputs,
            analyzer: analyzer,
            config: config)
        let md = CrossCapture.report(
            sessions: inputs,
            results: results,
            config: config)
        let outURL = resolveOutURL(
            reference: inputs[0].url,
            fallback: "cold_start_cross_capture.md")
        try md.write(to: outURL, atomically: true, encoding: .utf8)
        print("")
        print(CrossCapture.consoleSummary(results))
        print("ColdStartVerifier: cross-capture report → \(outURL.path)")
    }

    /// Load each session in `--sessions` (comma-separated). First-in-the-list
    /// is the reference. Each path must contain features.csv + raw_tap.wav.
    private func loadCrossCaptureSessions() throws -> [CrossCapture.SessionInputs] {
        let paths = sessions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard paths.count >= 2 else {
            throw ValidationError(
                "--cross-capture requires --sessions <a>,<b>[,<c>...] with at least 2 paths.")
        }
        var inputs: [CrossCapture.SessionInputs] = []
        for path in paths {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            print("ColdStartVerifier: loading session \(url.lastPathComponent)")
            let artifacts = try SessionArtifacts.load(directory: url)
            let rawTapURL = url.appendingPathComponent("raw_tap.wav")
            guard FileManager.default.fileExists(atPath: rawTapURL.path) else {
                throw VerifierError.missingRawTap(rawTapURL)
            }
            let rawTap = try RawTapAnalysis.analyze(url: rawTapURL)
            inputs.append(CrossCapture.SessionInputs(
                url: url,
                artifacts: artifacts,
                rawTap: rawTap))
        }
        return inputs
    }

    /// `--out` if provided, else `<reference>/<fallback>`.
    private func resolveOutURL(reference: URL, fallback: String) -> URL {
        if let out {
            return URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        }
        return reference.appendingPathComponent(fallback)
    }
}
