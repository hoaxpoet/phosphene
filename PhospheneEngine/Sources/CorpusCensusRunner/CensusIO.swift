// CensusIO — pure CSV / manifest / resume helpers for CorpusCensusRunner.
//
// No Metal, no audio, no I/O side effects on the pure functions — everything here
// is unit-tested in PhospheneEngineTests (CorpusCensusTests). Kept separate from
// main.swift so the test target can `@testable import CorpusCensusRunner` and
// exercise the fold-adjacent string plumbing without a Metal device.

import Foundation

// MARK: - CSV escaping (RFC 4180)

enum CensusCSV {

    /// Quote a single field per RFC 4180: wrap in double quotes and double any
    /// embedded quote iff the field contains a comma, quote, CR, or LF. Artist
    /// and album path segments contain commas ("Goodnight, Texas"), so this is
    /// load-bearing, not defensive.
    static func field(_ raw: String) -> String {
        let needsQuote = raw.contains(",") || raw.contains("\"")
            || raw.contains("\n") || raw.contains("\r")
        guard needsQuote else { return raw }
        return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Join pre-stringified fields into one RFC-4180 CSV record (no trailing newline).
    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// Split one CSV line into fields, honouring RFC-4180 quoting. Sufficient for
    /// the census's own output (no embedded newlines within a record) and for the
    /// pilot manifest. A trailing CR is stripped so `\r\n` files (Python's csv
    /// module writes these — the pilot manifest is one) parse identically to `\n`.
    static func parseLine(_ rawLine: String) -> [String] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var queued: Character?
        func next() -> Character? {
            if let head = queued { queued = nil; return head }
            return iterator.next()
        }
        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let peek = iterator.next() {
                        if peek == "\"" { current.append("\"") }      // escaped quote
                        else { inQuotes = false; queued = peek }        // closing quote
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                fields.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Resume set

enum CensusResume {

    /// The set of already-written relpaths in an existing output CSV — the first
    /// field of every data line (header skipped). Includes `#44100` / `#48000`
    /// dual-rate suffixed entries verbatim; the caller skips a manifest track when
    /// its (unsuffixed) relpath is present.
    static func doneRelpaths(fromCSV text: String) -> Set<String> {
        var done = Set<String>()
        // whereSeparator on isNewline: `\r\n` is a single grapheme cluster in Swift,
        // so split(separator: "\n") would NOT split CRLF files — this does.
        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            if index == 0 { continue }   // header
            let first = CensusCSV.parseLine(String(line)).first ?? ""
            if !first.isEmpty { done.insert(first) }
        }
        return done
    }
}

// MARK: - Manifest parsing

struct ManifestRow: Equatable {
    let relpath: String
    let tagStatus: String
}

enum CensusManifest {

    enum ParseError: Error, CustomStringConvertible {
        case missingColumn(String)
        var description: String {
            switch self {
            case .missingColumn(let name): return "manifest missing required column: \(name)"
            }
        }
    }

    /// Parse a pilot/full manifest CSV. Requires `relpath` and `tag_status` columns.
    /// Returns only rows whose `tag_status == "ok"` (m4p/part/unreadable rows are
    /// dropped) in file order.
    static func okRows(fromCSV text: String) throws -> [ManifestRow] {
        let lines = text.split(whereSeparator: \.isNewline)   // handles CRLF (see doneRelpaths)
        guard let headerLine = lines.first else { return [] }
        let header = CensusCSV.parseLine(String(headerLine))
        guard let relIdx = header.firstIndex(of: "relpath") else {
            throw ParseError.missingColumn("relpath")
        }
        guard let statusIdx = header.firstIndex(of: "tag_status") else {
            throw ParseError.missingColumn("tag_status")
        }
        var rows: [ManifestRow] = []
        for line in lines.dropFirst() {
            let fields = CensusCSV.parseLine(String(line))
            guard fields.count > max(relIdx, statusIdx) else { continue }
            let status = fields[statusIdx]
            guard status == "ok" else { continue }
            rows.append(ManifestRow(relpath: fields[relIdx], tagStatus: status))
        }
        return rows
    }
}

// MARK: - Output row schema

/// The 27-column census output row. Optional numeric fields render empty when
/// absent (decode/grid/stem failures) so a row is always append-able.
struct CensusRow {
    var relpath: String
    var durationS: Double?
    var nativeRate: Double?
    var windowS: Double?
    var gridBPM: Double?
    var gridBeatCount: Int?
    var barConfidence: Double?
    var drumsBPM: Double?
    var foldedDisagreement: Double?
    var beatIrregular: Bool?
    var mirBPM: Double?
    var valence: Double?
    var arousal: Double?
    var feats: [Double]        // 10 means, pre-normalization; empty ⇒ 10 blanks
    var keyClass: String
    var keyMajorR: Double?
    var keyMinorR: Double?
    var error: String

    init(
        relpath: String,
        durationS: Double? = nil,
        nativeRate: Double? = nil,
        windowS: Double? = nil,
        gridBPM: Double? = nil,
        gridBeatCount: Int? = nil,
        barConfidence: Double? = nil,
        drumsBPM: Double? = nil,
        foldedDisagreement: Double? = nil,
        beatIrregular: Bool? = nil,
        mirBPM: Double? = nil,
        valence: Double? = nil,
        arousal: Double? = nil,
        feats: [Double] = [],
        keyClass: String = "",
        keyMajorR: Double? = nil,
        keyMinorR: Double? = nil,
        error: String = ""
    ) {
        self.relpath = relpath
        self.durationS = durationS
        self.nativeRate = nativeRate
        self.windowS = windowS
        self.gridBPM = gridBPM
        self.gridBeatCount = gridBeatCount
        self.barConfidence = barConfidence
        self.drumsBPM = drumsBPM
        self.foldedDisagreement = foldedDisagreement
        self.beatIrregular = beatIrregular
        self.mirBPM = mirBPM
        self.valence = valence
        self.arousal = arousal
        self.feats = feats
        self.keyClass = keyClass
        self.keyMajorR = keyMajorR
        self.keyMinorR = keyMinorR
        self.error = error
    }

    static let header: [String] = [
        "relpath", "duration_s", "native_rate", "window_s",
        "grid_bpm", "grid_beat_count", "bar_confidence",
        "drums_bpm", "folded_disagreement", "beat_irregular",
        "mir_bpm",
        "valence", "arousal",
        "feat0", "feat1", "feat2", "feat3", "feat4",
        "feat5", "feat6", "feat7", "feat8", "feat9",
        "key_class", "key_major_r", "key_minor_r",
        "error",
    ]

    func csvLine() -> String {
        func num(_ value: Double?, _ places: Int = 4) -> String {
            guard let value, value.isFinite else { return "" }
            return String(format: "%.\(places)f", value)
        }
        var fields: [String] = [
            relpath,
            num(durationS, 2),
            num(nativeRate, 0),
            num(windowS, 1),
            num(gridBPM, 2),
            gridBeatCount.map(String.init) ?? "",
            num(barConfidence),
            num(drumsBPM, 2),
            num(foldedDisagreement, 5),
            beatIrregular.map { $0 ? "true" : "false" } ?? "",
            num(mirBPM, 2),
            num(valence),
            num(arousal),
        ]
        let feats10 = feats.count == 10 ? feats.map { num($0, 6) } : Array(repeating: "", count: 10)
        fields.append(contentsOf: feats10)
        fields.append(keyClass)
        fields.append(num(keyMajorR, 6))
        fields.append(num(keyMinorR, 6))
        fields.append(error)
        return CensusCSV.row(fields)
    }
}
