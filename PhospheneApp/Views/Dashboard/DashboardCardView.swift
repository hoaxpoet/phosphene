// DashboardCardView — Renders one `DashboardCardLayout` as SwiftUI
// (DASH.7 + DASH.7.1).
//
// Per DASH.7.1 brand-alignment (D-088): no per-card chrome. The card
// is now a typographic section — Clash Display title at 18pt, followed
// by rows. Container chrome (material panel + dividers) is shared at
// the `DashboardOverlayView` level. This honors the .impeccable.md
// anti-pattern "no rounded-rectangle cards … use whitespace and
// typography hierarchy instead".

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardCardView

struct DashboardCardView: View {
    let layout: DashboardCardLayout

    /// Lazily resolve once per app launch — the resolution is cached
    /// inside `DashboardFontLoader` so subsequent calls are free.
    private var fontResolution: DashboardFontLoader.FontResolution {
        DashboardFontLoader.resolveFonts(in: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.sm) {
            if !layout.title.isEmpty {
                Text(layout.title)
                    .font(.custom(
                        fontResolution.displayFontName,
                        size: DashboardTokens.TypeScale.bodyLarge,
                        relativeTo: .title3
                    ))
                    .foregroundColor(Color(nsColor: DashboardTokens.Color.textHeading))
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: layout.rowSpacing) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    DashboardRowView(row: row, fontResolution: fontResolution)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
