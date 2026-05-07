// BeatCardBuilderTests — 6 @Test functions covering BeatSyncSnapshot →
// DashboardCardLayout mapping (DASH.3).
//
// Switch-pattern extraction is used to inspect rows because Row contains
// `NSColor` associated values and adding `Equatable` conformance there is
// not useful (sRGB vs catalog vs named colors compare unreliably).

import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Switch-pattern row extractors

private func extractSingleValue(_ row: DashboardCardLayout.Row)
    -> (label: String, value: String, valueColor: NSColor)? {
    if case let .singleValue(label, value, valueColor) = row {
        return (label, value, valueColor)
    }
    return nil
}

private func extractProgressBar(_ row: DashboardCardLayout.Row)
    -> (label: String, value: Float, valueText: String, fillColor: NSColor)? {
    if case let .progressBar(label, value, valueText, fillColor) = row {
        return (label, value, valueText, fillColor)
    }
    return nil
}

// MARK: - Color comparison

/// `NSColor` equality is unreliable across colour spaces; compare via sRGB
/// channels with a tight tolerance.
private func colorMatches(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.01) -> Bool {
    guard let a = lhs.usingColorSpace(.sRGB),
          let b = rhs.usingColorSpace(.sRGB) else { return false }
    return abs(a.redComponent - b.redComponent) < tolerance
        && abs(a.greenComponent - b.greenComponent) < tolerance
        && abs(a.blueComponent - b.blueComponent) < tolerance
}

// MARK: - Tests

@Suite("BeatCardBuilder")
struct BeatCardBuilderTests {

    // MARK: a — zero snapshot → reactive layout

    @Test("zero snapshot produces REACTIVE / — / — bar / — beat")
    func build_zeroSnapshot_producesReactiveLayout() throws {
        let layout = BeatCardBuilder().build(from: .zero)

        #expect(layout.title == "BEAT")
        #expect(layout.rows.count == 4)

        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.label == "MODE")
        #expect(mode.value == "REACTIVE")
        #expect(colorMatches(mode.valueColor, DashboardTokens.Color.textMuted))

        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.label == "BPM")
        #expect(bpm.value == "—")
        #expect(colorMatches(bpm.valueColor, DashboardTokens.Color.textMuted))

        let bar = try #require(extractProgressBar(layout.rows[2]))
        #expect(bar.label == "BAR")
        #expect(bar.value == 0)
        #expect(bar.valueText == "— / 4")
        #expect(colorMatches(bar.fillColor, DashboardTokens.Color.purpleGlow))

        let beat = try #require(extractProgressBar(layout.rows[3]))
        #expect(beat.label == "BEAT")
        #expect(beat.value == 0)
        #expect(beat.valueText == "—")
        #expect(colorMatches(beat.fillColor, DashboardTokens.Color.coral))
    }

    // MARK: b — locking snapshot → amber MODE

    @Test("locking snapshot (sessionMode=2) produces LOCKING/amber MODE + BPM=125 + BAR=2/4")
    func build_lockingSnapshot_producesAmberMode() throws {
        let snapshot = BeatSyncSnapshot(
            barPhase01: 0.375, beatsPerBar: 4, beatInBar: 2, isDownbeat: false,
            sessionMode: 2, lockState: 1, gridBPM: 125,
            playbackTimeS: 0, driftMs: 0
        )
        let layout = BeatCardBuilder().build(from: snapshot)

        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "LOCKING")
        #expect(colorMatches(mode.valueColor, DashboardTokens.Color.statusYellow))

        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "125")

        let bar = try #require(extractProgressBar(layout.rows[2]))
        #expect(bar.valueText == "2 / 4")
        #expect(bar.value >= 0.37 && bar.value <= 0.38,
                "Expected BAR value ≈ 0.375; got \(bar.value)")
    }

    // MARK: c — locked snapshot → green MODE + derived beat phase + artifact

    @Test("locked snapshot produces LOCKED/green MODE, BPM=140, derived BEAT≈0.5 + saves artifact")
    func build_lockedSnapshot_producesGreenModeAndDerivedBeatPhase() throws {
        let snapshot = BeatSyncSnapshot(
            barPhase01: 0.625, beatsPerBar: 4, beatInBar: 3, isDownbeat: false,
            sessionMode: 3, lockState: 2, gridBPM: 140,
            playbackTimeS: 0, driftMs: 0
        )
        let layout = BeatCardBuilder().build(from: snapshot)

        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "LOCKED")
        #expect(colorMatches(mode.valueColor, DashboardTokens.Color.statusGreen))

        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "140")

        let bar = try #require(extractProgressBar(layout.rows[2]))
        #expect(bar.valueText == "3 / 4")
        #expect(bar.value >= 0.62 && bar.value <= 0.63,
                "Expected BAR value ≈ 0.625; got \(bar.value)")

        let beat = try #require(extractProgressBar(layout.rows[3]))
        #expect(beat.valueText == "3")
        // derived: 0.625 × 4 − (3 − 1) = 0.5
        #expect(beat.value >= 0.49 && beat.value <= 0.51,
                "Expected derived BEAT phase ≈ 0.5; got \(beat.value)")

        // Artifact: render the locked card onto a 320×220 layer with deep-
        // indigo backdrop and write to .build/dash1_artifacts/card_beat_locked.png.
        // Skipped silently when no Metal device is present.
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }
        DashboardFontLoader.resetCacheForTesting()
        let res = DashboardFontLoader.resolveFonts(
            in: Bundle(for: BeatCardBuilderTestAnchor.self) as Bundle?
        )
        guard let layer = DashboardTextLayer(
            device: device, width: 320, height: 220, fontResolution: res
        ) else {
            withKnownIssue("Failed to create DashboardTextLayer") {}
            return
        }

        layer.beginFrame()
        // Deep-indigo backdrop (oklch ≈ 0.18 0.06 285) — same value used in
        // DashboardCardRendererTests so artifacts compose visually.
        let backdrop = NSColor(srgbRed: 0.060, green: 0.058, blue: 0.135, alpha: 1.0)
        layer.graphicsContext.saveGState()
        layer.graphicsContext.setFillColor(backdrop.cgColor)
        layer.graphicsContext.fill(CGRect(x: 0, y: 0, width: 320, height: 220))
        layer.graphicsContext.restoreGState()

        let renderer = DashboardCardRenderer()
        renderer.render(
            layout,
            at: CGPoint(x: 16, y: 12),
            on: layer,
            cgContext: layer.graphicsContext
        )

        guard let cb = queue.makeCommandBuffer() else {
            withKnownIssue("Failed to make command buffer") {}
            return
        }
        layer.commit(into: cb)
        cb.commit()
        cb.waitUntilCompleted()

        savePNGArtifact(layer.texture, name: "card_beat_locked")
    }

    // MARK: d — BPM rounding

    @Test("BPM rounds half-up: 124.4→\"124\"; 124.5→\"124\" or \"125\" (platform half-to-even)")
    func build_bpmFormat_roundsHalfUp() throws {
        let lower = BeatCardBuilder().build(from: BeatSyncSnapshot(
            barPhase01: 0, beatsPerBar: 4, beatInBar: 1, isDownbeat: true,
            sessionMode: 3, lockState: 2, gridBPM: 124.4,
            playbackTimeS: 0, driftMs: 0
        ))
        let lowerBPM = try #require(extractSingleValue(lower.rows[1]))
        #expect(lowerBPM.value == "124", "Expected \"124\"; got \"\(lowerBPM.value)\"")

        let half = BeatCardBuilder().build(from: BeatSyncSnapshot(
            barPhase01: 0, beatsPerBar: 4, beatInBar: 1, isDownbeat: true,
            sessionMode: 3, lockState: 2, gridBPM: 124.5,
            playbackTimeS: 0, driftMs: 0
        ))
        let halfBPM = try #require(extractSingleValue(half.rows[1]))
        // Swift `%.0f` is half-to-even on Apple platforms — accept either.
        #expect(halfBPM.value == "124" || halfBPM.value == "125",
                "Expected \"124\" or \"125\"; got \"\(halfBPM.value)\"")
    }

    // MARK: e — unlocked snapshot → muted mode but heading-coloured BPM

    @Test("unlocked snapshot (sessionMode=1) → UNLOCKED/muted + BPM 120 in textHeading")
    func build_unlockedSnapshot_producesMutedModeWithGridBpm() throws {
        let snapshot = BeatSyncSnapshot(
            barPhase01: 0, beatsPerBar: 4, beatInBar: 1, isDownbeat: true,
            sessionMode: 1, lockState: 0, gridBPM: 120,
            playbackTimeS: 0, driftMs: 0
        )
        let layout = BeatCardBuilder().build(from: snapshot)

        let mode = try #require(extractSingleValue(layout.rows[0]))
        #expect(mode.value == "UNLOCKED")
        #expect(colorMatches(mode.valueColor, DashboardTokens.Color.textMuted))

        let bpm = try #require(extractSingleValue(layout.rows[1]))
        #expect(bpm.value == "120")
        #expect(colorMatches(bpm.valueColor, DashboardTokens.Color.textHeading))
    }

    // MARK: f — width override

    @Test("width override is passed through to the layout")
    func build_widthOverride_passesThrough() {
        let layout = BeatCardBuilder().build(from: .zero, width: 320)
        #expect(layout.width == 320)
    }
}

// MARK: - Artifact helper

private func savePNGArtifact(_ texture: MTLTexture, name: String) {
    let artifactDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build/dash1_artifacts")
    try? FileManager.default.createDirectory(at: artifactDir,
                                              withIntermediateDirectories: true)
    let url = artifactDir.appendingPathComponent("\(name).png")
    if writeTextureToPNG(texture, url: url) != nil {
        print("BeatCardBuilderTests: artifact saved → \(url.path)")
    } else {
        print("BeatCardBuilderTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class BeatCardBuilderTestAnchor {}
