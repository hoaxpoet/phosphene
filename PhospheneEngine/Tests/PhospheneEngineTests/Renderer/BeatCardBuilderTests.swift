// BeatCardBuilderTests — Pure data assertions for `BeatCardBuilder`.
// DASH.7 rewrite: artifact-rendering tail removed (Metal renderer retired
// in favour of SwiftUI; the SwiftUI views render the same layouts).

import CoreGraphics
import Foundation
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Fixtures

private func snapshot(
    bpm: Float = 125,
    beatsPerBar: Int = 4,
    beatInBar: Int = 2,
    barPhase01: Float = 0.25,
    sessionMode: Int = 3,
    lockState: Int = 2
) -> BeatSyncSnapshot {
    BeatSyncSnapshot(
        barPhase01: barPhase01,
        beatsPerBar: beatsPerBar,
        beatInBar: beatInBar,
        isDownbeat: beatInBar == 1,
        sessionMode: sessionMode,
        lockState: lockState,
        gridBPM: bpm,
        playbackTimeS: 1.0,
        driftMs: 5.0
    )
}

private func extractSingleValue(_ row: DashboardCardLayout.Row) -> (label: String, value: String, color: NSColor)? {
    if case let .singleValue(label, value, color) = row {
        return (label, value, color)
    }
    return nil
}

private func extractProgressBar(_ row: DashboardCardLayout.Row) -> (label: String, value: Float, valueText: String, color: NSColor)? {
    if case let .progressBar(label, value, valueText, color) = row {
        return (label, value, valueText, color)
    }
    return nil
}

private func colorEquals(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    let l = lhs.usingColorSpace(.sRGB) ?? lhs
    let r = rhs.usingColorSpace(.sRGB) ?? rhs
    return abs(l.redComponent - r.redComponent) < 0.001
        && abs(l.greenComponent - r.greenComponent) < 0.001
        && abs(l.blueComponent - r.blueComponent) < 0.001
}

// MARK: - Suite

@Suite("BeatCardBuilder")
struct BeatCardBuilderTests {

    @Test("locked snapshot produces LOCKED/green MODE, BPM=140, BAR=2/4")
    func locked() throws {
        let layout = BeatCardBuilder().build(from: snapshot(bpm: 140, sessionMode: 3))
        #expect(layout.title == "BEAT")
        #expect(layout.rows.count == 4)
        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.label == "MODE")
        #expect(mode.value == "LOCKED")
        #expect(colorEquals(mode.color, DashboardTokens.Color.statusGreen))
        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "140")
    }

    @Test("locking snapshot (sessionMode=2) → LOCKING/yellow MODE")
    func locking() throws {
        let layout = BeatCardBuilder().build(from: snapshot(sessionMode: 2))
        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "LOCKING")
        #expect(colorEquals(mode.color, DashboardTokens.Color.statusYellow))
    }

    @Test("unlocked snapshot (sessionMode=1) → UNLOCKED/muted")
    func unlocked() throws {
        let layout = BeatCardBuilder().build(from: snapshot(sessionMode: 1))
        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "UNLOCKED")
        #expect(colorEquals(mode.color, DashboardTokens.Color.textMuted))
    }

    @Test("zero snapshot produces REACTIVE / — / — bar / — beat")
    func zero() throws {
        let layout = BeatCardBuilder().build(from: .zero)
        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "REACTIVE")
        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "—")
        let bar = try #require(extractProgressBar(layout.rows[2]))
        #expect(bar.value == 0)
        #expect(bar.valueText == "— / 4")
    }

    @Test("BPM rounds half-up (platform half-to-even tolerated)")
    func bpmRounding() throws {
        let layout = BeatCardBuilder().build(from: snapshot(bpm: 124.4))
        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "124")
    }

    @Test("width override is passed through to the layout")
    func widthOverride() {
        let layout = BeatCardBuilder().build(from: snapshot(), width: 360)
        #expect(layout.width == 360)
    }
}
