// PerformanceToastLayoutTests — a toast is as tall as its copy, wherever it is placed. (BUG-113)
//
// Inside the chrome the toast region is offered the whole window height. Before DS.6
// the toast's accent bar — a `Color` — accepted that offer, and every toast rendered as a
// floor-to-ceiling panel over the cluster (found by the DS.6 capture harness, confirmed
// live). This hosts one toast exactly the way `PlaybackChromeView` does — inside a tall
// frame, bottom-trailing — renders it, and measures the accent bar: it must stay a strip.

import AppKit
import SwiftUI
import Testing
@testable import UzumeApp

@Suite("PerformanceToast layout")
@MainActor
struct PerformanceToastLayoutTests {

    @Test("offered the whole window, a one-line toast stays one line tall")
    func toast_doesNotStretchToProposedHeight() async throws {
        let toast = UzumeToast(severity: .info, copy: "Display connected.")
        let view = ZStack {
            UzumeAppColor.canvas
            PerformanceToast(toast: toast, onDismiss: { _ in })
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 960, height: 600)

        let bounds = CGRect(x: 0, y: 0, width: 960, height: 600)
        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark))
        hosting.frame = bounds
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / bounds.width
        let accentHeight = accentBarHeight(in: rep, scale: scale)
        #expect(accentHeight > 0, "the accent bar was not found in the render")
        #expect(accentHeight < 100, "accent bar is \(Int(accentHeight)) pt tall — the toast stretched (BUG-113)")
    }

    /// Height in points of the tallest run of info-blue pixels in any column — the accent
    /// bar's height, since nothing else in the render is that colour.
    private func accentBarHeight(in rep: NSBitmapImageRep, scale: CGFloat) -> CGFloat {
        var best = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            var run = 0
            for y in 0..<rep.pixelsHigh {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                // --color-status-info-foreground #64D2FF under the toast's 35 % black tint
                // lands near (0.25, 0.53, 0.65): blue-dominant, well clear of the grey copy.
                let isInfoBlue = pixel.blueComponent > 0.45
                    && pixel.blueComponent > pixel.redComponent + 0.25
                    && pixel.greenComponent > pixel.redComponent
                run = isInfoBlue ? run + 1 : 0
                best = max(best, run)
            }
        }
        return CGFloat(best) / scale
    }
}
