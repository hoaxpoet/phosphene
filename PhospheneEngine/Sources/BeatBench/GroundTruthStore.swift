// GroundTruthStore + BaselineReport — GT.2 artifacts in, baseline table out.
//
// Ground truth is whatever GT.2's reconciliation committed. Tracks whose meter or
// beats could not be determined (Pyramid Song's meter, Clair de Lune's grid) carry
// that state explicitly — the report prints it rather than omitting the row, because
// a silently absent row reads as "nothing to see" when it is in fact the finding.

import Foundation

// MARK: - Ground truth

struct GroundTruth {
    let trackID: String
    let suite: Int
    let status: String
    let beats: [Double]
    let downbeats: [Double]
    let bpm: Double?
    let meter: Int?
    let audioFile: String?
}

enum GroundTruthStore {

    private struct Document: Decodable {
        let trackID: String
        let suite: Int
        let status: String
        let beatsS: [Double]
        let downbeatsS: [Double]
        let tapBPM: Double?
        let meterFromTaps: Int?

        enum CodingKeys: String, CodingKey {
            case trackID = "track_id"
            case suite
            case status
            case beatsS = "beats_s"
            case downbeatsS = "downbeats_s"
            case tapBPM = "tap_bpm"
            case meterFromTaps = "meter_from_taps"
        }
    }

    private struct Manifest: Decodable {
        struct Track: Decodable {
            let id: String
            let filename: String?
        }
        let tracks: [Track]
    }

    static func load(dir: URL, filter: Set<String>) throws -> [GroundTruth] {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        var filenames: [String: String] = [:]
        for track in manifest.tracks { filenames[track.id] = track.filename }

        let truthDir = dir.appendingPathComponent("groundtruth")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: truthDir, includingPropertiesForKeys: nil
        )) ?? []

        var results: [GroundTruth] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let doc = try? JSONDecoder().decode(Document.self, from: data)
            else { continue }
            if !filter.isEmpty && !filter.contains(doc.trackID) { continue }
            results.append(GroundTruth(
                trackID: doc.trackID,
                suite: doc.suite,
                status: doc.status,
                beats: doc.beatsS,
                downbeats: doc.downbeatsS,
                bpm: doc.tapBPM,
                meter: doc.meterFromTaps,
                audioFile: filenames[doc.trackID]
            ))
        }
        return results
    }
}

// MARK: - Report

struct BaselineRow {
    let trackID: String
    let suite: Int
    let status: String
    let truthBPM: Double?
    let gridBPM: Double
    let truthMeter: Int?
    let gridMeter: Int
    let scores: BeatScores
    let downbeatF: Double?
}

enum BaselineReport {

    static func line(for row: BaselineRow) -> String {
        let truthBPM = row.truthBPM.map { String(format: "%.2f", $0) } ?? "—"
        let meter = row.truthMeter.map(String.init) ?? "—"
        let downbeat = row.downbeatF.map { String(format: "%.2f", $0) } ?? "—"
        let scores = row.scores
        let head = "  s\(row.suite) \(row.trackID.padding(toLength: 20, withPad: " ", startingAt: 0))"
        let tempo = "truth \(truthBPM)  grid \(String(format: "%.2f", row.gridBPM))"
        let meters = "meter \(meter)/\(row.gridMeter)"
        let metrics = "F \(String(format: "%.2f", scores.fMeasure))"
            + "  Cem \(String(format: "%.2f", scores.cemgil))"
            + "  CMLt \(String(format: "%.2f", scores.cmlt))"
            + "  AMLt \(String(format: "%.2f", scores.amlt))"
            + "  dbF \(downbeat)"
        return "\(head)  \(tempo)  \(meters)  \(metrics)"
    }

    static func render(rows: [BaselineRow]) -> String {
        var out = ["| suite | track | truth BPM | grid BPM | meter t/g | F | Cemgil | CMLt | AMLt | downbeat F |",
                   "|---|---|---|---|---|---|---|---|---|---|"]
        for row in rows {
            let truthBPM = row.truthBPM.map { String(format: "%.2f", $0) } ?? "—"
            let meter = "\(row.truthMeter.map(String.init) ?? "—")/\(row.gridMeter)"
            let downbeat = row.downbeatF.map { String(format: "%.2f", $0) } ?? "—"
            let sc = row.scores
            let cells = [
                "\(row.suite)", row.trackID, truthBPM,
                String(format: "%.2f", row.gridBPM), meter,
                String(format: "%.2f", sc.fMeasure), String(format: "%.2f", sc.cemgil),
                String(format: "%.2f", sc.cmlt), String(format: "%.2f", sc.amlt), downbeat,
            ]
            out.append("| " + cells.joined(separator: " | ") + " |")
        }
        return out.joined(separator: "\n")
    }

    static func document(rows: [BaselineRow]) -> String {
        let bySuite = Dictionary(grouping: rows, by: \.suite)
        var lines = [
            "# BeatBench baseline — Phosphene's prep-time grid vs GT.2 ground truth",
            "",
            "Generated by `swift run BeatBench --mode offline-grid`. Ground truth is GT.2:",
            "Matt's taps, cross-checked against madmom and librosa. Beat This! is deliberately",
            "not a ground-truth source — it *is* Phosphene's grid model (D-077), so scoring",
            "against it would be circular.",
            "",
            "**This is the offline/prep-time path only.** The live path (session replay) is a",
            "GT.3 follow-up; numbers here do not include live drift.",
            "",
            render(rows: rows),
            "",
            "## Per-suite summary",
            "",
            "| suite | tracks | mean F | mean CMLt | mean AMLt |",
            "|---|---|---|---|---|",
        ]
        for suite in bySuite.keys.sorted() {
            guard let group = bySuite[suite], !group.isEmpty else { continue }
            let count = Double(group.count)
            let meanF = group.map(\.scores.fMeasure).reduce(0, +) / count
            let meanCMLt = group.map(\.scores.cmlt).reduce(0, +) / count
            let meanAMLt = group.map(\.scores.amlt).reduce(0, +) / count
            let cells = [
                "\(suite)", "\(group.count)",
                String(format: "%.2f", meanF),
                String(format: "%.2f", meanCMLt),
                String(format: "%.2f", meanAMLt),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")
        lines.append("Metric definitions and windows: the `beatbench` skill. F and downbeat F use")
        lines.append("±70 ms one-to-one matching; Cemgil σ = 40 ms; continuity tolerance 17.5 %.")
        lines.append("AMLt accepts double/half/offbeat readings, CMLt does not — a large AMLt−CMLt")
        lines.append("gap means the grid found the pulse but not the metrical level.")
        return lines.joined(separator: "\n") + "\n"
    }
}
