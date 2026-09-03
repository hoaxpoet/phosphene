// PlaybackChromeReducedMotionTests — under reduced motion the chrome holds still. (DS.6)
//
// DESIGN.md §Shared States and Motion: reduced motion removes continuous animation.
// The two chrome surfaces that animate on their own — the reactive-mode pulse in the
// session dots and the listening badge's spinner — both guard their `repeatForever`
// on `reduceMotion`. This renders them with it on, twice, and asserts the pixels did
// not move. A regression that starts either animation unconditionally fails here.

import AppKit
import SwiftUI
import Testing
@testable import UzumeApp

@Suite("PlaybackChrome reduced motion")
@MainActor
struct PlaybackChromeReducedMotionTests {

    @Test("reduced motion renders the cluster and the badge without a repeating animation")
    func reducedMotion_holdsStill() async throws {
        let reactive = SessionProgressData(totalTracks: 0, currentIndex: -1, isReactiveMode: true)
        let view = HStack(spacing: 24) {
            PlaybackControlsCluster(
                progress: reactive,
                reduceMotion: true,
                showTrackInformation: .constant(true),
                onSettings: {},
                onEndSession: {}
            )
            ListeningBadgeView(isVisible: true, reduceMotion: true)
        }
        .padding(24)
        .background(UzumeAppColor.canvas)

        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let bounds = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.frame = bounds
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }

        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let first = try snapshot(hosting, bounds: bounds)
        try await Task.sleep(for: .milliseconds(450))   // ~half a pulse period, ~a third of a spin
        let second = try snapshot(hosting, bounds: bounds)

        #expect(!first.isEmpty)
        #expect(first == second, "something in the chrome kept animating under reduced motion")
    }

    private func snapshot(_ view: NSView, bounds: CGRect) throws -> Data {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.noBitmap
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.noBitmap
        }
        return png
    }

    private enum SnapshotError: Error { case noBitmap }
}
