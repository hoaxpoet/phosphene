// DashboardOverlayView — Top-trailing dashboard panel (DASH.7 + DASH.7.1).
//
// Single material-backed panel containing three typographic sections
// (BEAT / STEMS / PERF) separated by thin dividers. Replaces the DASH.6
// per-card rounded-rectangle chrome — the .impeccable.md anti-pattern
// "rounded-rectangle cards with drop shadows as the primary UI pattern"
// is corrected to "use whitespace and typography hierarchy instead"
// (D-088). The shared `.regularMaterial` is the project's purposeful
// glassmorphism — `NSVisualEffectView` under the hood per the macOS
// design notes.
//
// Visibility is gated by `showDebug` in PlaybackView; the parent attaches
// a spring transition so the panel descends quietly into view rather than
// popping (.impeccable.md transition spec).

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardOverlayView

/// Top-trailing column of three dashboard sections.
struct DashboardOverlayView: View {

    @ObservedObject var viewModel: DashboardOverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.layouts.enumerated()), id: \.element.title) { index, layout in
                if index > 0 {
                    Divider()
                        .background(Color(nsColor: DashboardTokens.Color.border))
                }
                DashboardCardView(layout: layout)
                    .padding(.vertical, DashboardTokens.Spacing.md)
            }
        }
        .padding(.horizontal, DashboardTokens.Spacing.lg)
        .padding(.vertical, DashboardTokens.Spacing.sm)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(.top, DashboardTokens.Spacing.lg)
        .padding(.trailing, DashboardTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // The SwiftUI debug overlay carries a11y; cards are visual.
    }
}
