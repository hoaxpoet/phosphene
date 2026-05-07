// DashboardOverlayView — Top-right dashboard cards (DASH.7).
//
// SwiftUI overlay rendering BEAT / STEMS / PERF cards. Sits as PlaybackView
// Layer 6 (above the bottom-leading DebugOverlayView). Visibility is gated
// by the same `showDebug` state PlaybackView already drives via the `D`
// shortcut — one toggle, two complementary surfaces (instruments vs raw
// diagnostics).
//
// Replaces the DASH.6 Metal composer (D-086 → D-087). The Sendable card
// builders survive unchanged; only the rendering layer changed.

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardOverlayView

/// Top-right column of dashboard cards (BEAT / STEMS / PERF).
struct DashboardOverlayView: View {

    @ObservedObject var viewModel: DashboardOverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.cardGap) {
            ForEach(Array(viewModel.layouts.enumerated()), id: \.offset) { _, layout in
                DashboardCardView(layout: layout)
            }
        }
        .padding(.top, DashboardTokens.Spacing.lg)
        .padding(.trailing, DashboardTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // Cards are purely visual; the SwiftUI debug overlay carries the a11y story.
    }
}
