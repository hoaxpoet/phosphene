// CorpusCensusTests — pure-function coverage for CENSUS.2's I/O plumbing plus the
// foldedBPMDisagreement extraction it shares with the production D-154 gate.
// No Metal, no audio files (FA #27: real-music behaviour is validated dev-local,
// not with synthetic fixtures).

import XCTest
@testable import CorpusCensusRunner
import Session

final class CorpusCensusTests: XCTestCase {

    // MARK: - foldedBPMDisagreement (shared with assessBeatIrregularity)

    func testFold_identical_isZero() {
        XCTAssertEqual(foldedBPMDisagreement(120, 120)!, 0, accuracy: 1e-9)
    }

    func testFold_exactOctaves_areClean() {
        XCTAssertEqual(foldedBPMDisagreement(60, 120)!, 0, accuracy: 1e-9)   // 2:1
        XCTAssertEqual(foldedBPMDisagreement(120, 60)!, 0, accuracy: 1e-9)   // 1:2 (order-agnostic)
        XCTAssertEqual(foldedBPMDisagreement(30, 120)!, 0, accuracy: 1e-9)   // 4:1
    }

    func testFold_pyramidSong_57pctRaw_foldsToAbout17pct() {
        // |100-233|/233 ≈ 0.571 raw; max/min = 2.33 → fold 1.165 → dist 0.165.
        // The D-154 narrative's Pyramid Song case: ~57 % raw / ~17 % folded.
        XCTAssertEqual(foldedBPMDisagreement(100, 233)!, 0.165, accuracy: 0.02)
    }

    func testFold_justUnderTwo_edge_isNearZero() {
        // 199:100 folds to 1.99 → distance to 2.0 = 0.01, NOT 0.99.
        XCTAssertEqual(foldedBPMDisagreement(100, 199)!, 0.01, accuracy: 1e-9)
    }

    func testFold_nonFiniteOrZero_isNil() {
        XCTAssertNil(foldedBPMDisagreement(0, 120))
        XCTAssertNil(foldedBPMDisagreement(120, 0))
        XCTAssertNil(foldedBPMDisagreement(.nan, 120))
        XCTAssertNil(foldedBPMDisagreement(120, .infinity))
        XCTAssertNil(foldedBPMDisagreement(-120, 120))
    }

    func testAssessBeatIrregularity_unchanged() {
        // Behaviour pinned: regular octave pair → false; Pyramid-scale → true;
        // low bar confidence → true; missing estimator → nil.
        XCTAssertEqual(assessBeatIrregularity(gridBPM: 120, drumsBPM: 120, barConfidence: 0.9), false)
        XCTAssertEqual(assessBeatIrregularity(gridBPM: 60, drumsBPM: 120, barConfidence: 0.9), false)
        XCTAssertEqual(assessBeatIrregularity(gridBPM: 100, drumsBPM: 233, barConfidence: 0.9), true)
        XCTAssertEqual(assessBeatIrregularity(gridBPM: 120, drumsBPM: 120, barConfidence: 0.1), true)
        XCTAssertNil(assessBeatIrregularity(gridBPM: 0, drumsBPM: 120, barConfidence: 0.9))
    }

    // MARK: - CSV escaping (RFC 4180)

    func testCSV_escapesCommaQuoteUnicode() {
        XCTAssertEqual(CensusCSV.field("plain"), "plain")
        XCTAssertEqual(CensusCSV.field("Goodnight, Texas"), "\"Goodnight, Texas\"")
        XCTAssertEqual(CensusCSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CensusCSV.field("Björk/Vespertine"), "Björk/Vespertine")   // unicode, no quoting
    }

    func testCSV_roundTrip_commaQuoteUnicode() {
        let fields = ["A/Sigur Rós/( )", "Goodnight, Texas", "quote \" here", "café", "trailing,"]
        let line = CensusCSV.row(fields)
        XCTAssertEqual(CensusCSV.parseLine(line), fields)
    }

    // MARK: - Resume set

    func testResume_collectsFirstFields_includingDualRateSuffixes() {
        let csv = """
        relpath,duration_s,error
        A/artist/album/01.mp3,240.0,
        "B/x, y/album/02.flac",190.0,
        A/artist/album/03.m4a#44100,,
        A/artist/album/03.m4a#48000,,
        """
        let done = CensusResume.doneRelpaths(fromCSV: csv)
        XCTAssertEqual(done, [
            "A/artist/album/01.mp3",
            "B/x, y/album/02.flac",
            "A/artist/album/03.m4a#44100",
            "A/artist/album/03.m4a#48000",
        ])
        // Skip predicate: the unsuffixed native relpath is the resume key.
        XCTAssertTrue(done.contains("A/artist/album/01.mp3"))
        XCTAssertFalse(done.contains("A/artist/album/03.m4a"))   // only suffixed rows present
    }

    // MARK: - Manifest parsing

    func testManifest_requiresColumns_andSkipsNonOk() throws {
        let csv = """
        relpath,ext,tag_status,stratum
        A/a/al/01.mp3,mp3,ok,jazz
        A/a/al/02.m4p,m4p,unreadable,prop
        "B/x, y/al/03.flac",flac,ok,flac
        A/a/al/04.part,part,error,prop
        """
        let rows = try CensusManifest.okRows(fromCSV: csv)
        XCTAssertEqual(rows.map(\.relpath), ["A/a/al/01.mp3", "B/x, y/al/03.flac"])
    }

    func testManifest_missingColumn_throws() {
        let csv = "ext,tag_status\nmp3,ok"
        XCTAssertThrowsError(try CensusManifest.okRows(fromCSV: csv))
    }

    func testManifest_crlfLineEndings_parse() throws {
        // The pilot manifest is written by Python's csv module → \r\n endings.
        let csv = "relpath,tag_status,stratum\r\nA/a/al/01.mp3,ok,jazz\r\nA/a/al/02.m4p,unreadable,prop\r\n"
        let rows = try CensusManifest.okRows(fromCSV: csv)
        XCTAssertEqual(rows.map(\.relpath), ["A/a/al/01.mp3"])
        XCTAssertEqual(rows.first?.tagStatus, "ok")   // not "ok\r"
    }

    // MARK: - Output row shape

    func testRow_headerCount_matchesFieldCount() {
        let row = CensusRow(
            relpath: "A/a/al/01.mp3", durationS: 240.5, nativeRate: 44100, windowS: 30,
            gridBPM: 118.2, gridBeatCount: 59, barConfidence: 0.83, drumsBPM: 118.1,
            foldedDisagreement: 0.004, beatIrregular: false, mirBPM: 120.0,
            valence: 0.12, arousal: -0.30, feats: Array(repeating: 0.5, count: 10),
            keyClass: "C", keyMajorR: 0.61, keyMinorR: 0.44, error: ""
        )
        let fields = CensusCSV.parseLine(row.csvLine())
        XCTAssertEqual(fields.count, CensusRow.header.count)
        XCTAssertEqual(CensusRow.header.count, 27)
        XCTAssertEqual(fields[0], "A/a/al/01.mp3")
        XCTAssertEqual(fields.last, "")
    }

    func testRow_missingValues_renderEmpty_notZero() {
        let row = CensusRow.parseBlankForTest(relpath: "x.mp3", error: "decode failed")
        let fields = CensusCSV.parseLine(row.csvLine())
        XCTAssertEqual(fields.count, 27)
        XCTAssertEqual(fields[1], "")                 // duration_s empty, not "0.00"
        XCTAssertEqual(fields.last, "decode failed")
    }
}

// Small test-only shim so the blank-row factory (private to main.swift) has an
// equivalent here without exposing production plumbing.
private extension CensusRow {
    static func parseBlankForTest(relpath: String, error: String) -> CensusRow {
        CensusRow(
            relpath: relpath, durationS: nil, nativeRate: nil, windowS: nil,
            gridBPM: nil, gridBeatCount: nil, barConfidence: nil, drumsBPM: nil,
            foldedDisagreement: nil, beatIrregular: nil, mirBPM: nil,
            valence: nil, arousal: nil, feats: [], keyClass: "",
            keyMajorR: nil, keyMinorR: nil, error: error
        )
    }
}
