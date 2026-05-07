// DashboardOverlayView — Top-trailing dashboard panel (DASH.7 + DASH.7.1
// + DASH.7.2).
//
// Single dark-vibrancy panel containing three typographic sections
// (BEAT / STEMS / PERF) separated by thin dividers. Replaces the DASH.6
// per-card rounded-rectangle chrome — the .impeccable.md anti-pattern
// "rounded-rectangle cards with drop shadows as the primary UI pattern"
// is corrected to "use whitespace and typography hierarchy instead"
// (D-088). The shared backdrop is `DarkVibrancyView` (NSVisualEffectView
// pinned to `.vibrantDark`) over an explicit `surface` tint at 0.55α —
// guarantees a Phosphene-purple dark surface even on macOS Light
// appearance (D-089). The whole subtree is also locked to
// `.environment(\.colorScheme, .dark)` so any inherited SwiftUI tokens
// resolve to dark variants.
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
        .background {
            ZStack {
                // Vibrant-dark NSVisualEffectView. Always dark regardless of
                // system appearance (D-089).
                DarkVibrancyView()
                // Phosphene `surface` tint at 0.96α over the vibrancy. The
                // dashboard sits over the visualizer, which can render any
                // colour — to guarantee WCAG AA contrast for body/teal/coral
                // text in the worst case (a bright preset frame underneath),
                // the surface must be near-opaque. Vibrancy stays as a thin
                // backdrop softener at the edges; the 4% remaining
                // translucency is decorative, not load-bearing.
                Color(nsColor: DashboardTokens.Color.surface).opacity(0.96)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: DashboardTokens.Color.border).opacity(0.6), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .padding(.top, DashboardTokens.Spacing.lg)
        .padding(.trailing, DashboardTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // The SwiftUI debug overlay carries a11y; cards are visual.
    }
}
