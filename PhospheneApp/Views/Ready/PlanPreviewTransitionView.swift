// PlanPreviewTransitionView — Between-row glyph showing transition style (U.5 Part B).

import SwiftUI

// MARK: - PlanPreviewTransitionView

/// Small connector rendered between two `PlanPreviewRowView` instances.
///
/// Shows the outgoing transition style and duration for the preceding track.
struct PlanPreviewTransitionView: View {

    let summary: TransitionSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.caption2.weight(.light))
                .foregroundColor(.white.opacity(0.3))

            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 56)
        .padding(.vertical, 2)
    }

    private var label: String {
        switch summary.style {
        case "cut":
            return summary.isStructural
                ? String(localized: "plan_preview.transition.cut_structural")
                : String(localized: "plan_preview.transition.cut")
        case "crossfade":
            if let dur = summary.duration {
                return String(format: String(localized: "plan_preview.transition.crossfade_duration"), dur)
            }
            return String(localized: "plan_preview.transition.crossfade")
        case "morph":
            if let dur = summary.duration {
                return String(format: String(localized: "plan_preview.transition.morph_duration"), dur)
            }
            return String(localized: "plan_preview.transition.morph")
        default:
            return summary.style
        }
    }
}
