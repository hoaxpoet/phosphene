// DashboardCardView — Renders one `DashboardCardLayout` as SwiftUI (DASH.7).
//
// Painting order: chrome (rounded `Color.surfaceRaised`@0.92α + 1px
// `Color.border` stroke) → title → rows. The rounded chrome is the .impeccable
// "purposeful glassmorphism" exception (D-082) — kept identical to DASH.6.
//
// Width is fixed at `layout.width` to honor the design contract; height
// reflows to match `rows.reduce(...)` since DASH.7 cards may include or
// omit rows based on state (PerfCardBuilder hides QUALITY / ML when healthy).

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardCardView

struct DashboardCardView: View {
    let layout: DashboardCardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.rowSpacing) {
            if !layout.title.isEmpty {
                Text(layout.title)
                    .font(.system(size: layout.titleSize, weight: .medium))
                    .tracking(DashboardTokens.TypeScale.labelTracking)
                    .foregroundColor(Color(nsColor: DashboardTokens.Color.textBody))
            }
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                DashboardRowView(row: row)
            }
        }
        .padding(layout.padding)
        .frame(width: layout.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.xs)
                .fill(Color(nsColor: DashboardTokens.Color.surfaceRaised).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.xs)
                .strokeBorder(Color(nsColor: DashboardTokens.Color.border), lineWidth: 1)
        )
    }
}
