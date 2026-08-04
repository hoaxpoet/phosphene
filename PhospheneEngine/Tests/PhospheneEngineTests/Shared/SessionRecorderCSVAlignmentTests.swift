// SessionRecorderCSVAlignmentTests — the columns must line up with their names.
//
// DYN.1 shipped a row whose LAST column group carried the terminating newline while a
// newer group was appended after it. Every frame's two density values were therefore
// written at the head of the FOLLOWING line, shifting every column by two for the whole
// session. The file still had a plausible field count per line, so nothing caught it —
// it surfaced only as impossible values during analysis (a negative energy ratio, and
// `time` reading 0.115 on a row 500 frames in).
//
// The invariant is simple and worth gating: the newline is LAST, and the row has exactly
// as many fields as the header has names. Anything appending a column trips this if it
// gets the order wrong.

import Testing
import Foundation
@testable import Shared

@Suite("SessionRecorder CSV column alignment")
struct SessionRecorderCSVAlignmentTests {

    @Test("a features row has exactly as many fields as the header has names")
    func featuresRowFieldCountMatchesHeader() {
        let header = SessionRecorder.featuresCSVHeader
            .replacingOccurrences(of: "\n", with: "")
            .split(separator: ",", omittingEmptySubsequences: false)
        var fv = FeatureVector()
        fv.spectralDensity = 0.25
        fv.spectralDensitySlow = 0.20
        let row = SessionRecorder.csvRow(features: fv, frame: 1, wallclock: 0)

        #expect(row.hasSuffix("\n"), "the row must end with a newline, and it must be LAST")
        #expect(!row.dropLast().contains("\n"), """
            the row contains an INTERIOR newline — a column group is terminating the line \
            before later groups are appended, so those values land on the next row and \
            shift every column. This is the DYN.1 bug, and it is invisible in the field \
            count: check the order of the `+` chain in `csvRow(features:)`.
            """)

        let fields = row.trimmingCharacters(in: .newlines)
            .split(separator: ",", omittingEmptySubsequences: false)
        #expect(fields.count == header.count, """
            row has \(fields.count) fields against \(header.count) header names — a column \
            was added to one and not the other.
            """)
    }

    @Test("a stems row has exactly as many fields as its header has names")
    func stemsRowFieldCountMatchesHeader() {
        let header = SessionRecorder.stemsCSVHeader
            .replacingOccurrences(of: "\n", with: "")
            .split(separator: ",", omittingEmptySubsequences: false)
        let row = SessionRecorder.csvRow(stems: .zero, frame: 1, wallclock: 0)
        #expect(!row.dropLast().contains("\n"), "interior newline in the stems row")
        let fields = row.trimmingCharacters(in: .newlines)
            .split(separator: ",", omittingEmptySubsequences: false)
        #expect(fields.count == header.count, """
            stems row has \(fields.count) fields against \(header.count) header names.
            """)
    }
}
