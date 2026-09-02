// PreparationStatusIndicator — the 28 × 28 pt mark beside a preparation row. (DS.4)
//
// Extracted from TrackPreparationStatusIcon. A spinner for in-flight statuses; an SF
// Symbol in the matching status token for the terminal ones. Tokens only (D-232).

import Session
import SwiftUI

// MARK: - PreparationStatusIndicator

/// Single-glyph status for one track in the preparation list.
struct PreparationStatusIndicator: View {
    static let size: CGFloat = 28

    let status: TrackPreparationStatus

    var body: some View {
        ZStack {
            switch status {
            case .queued:
                Image(systemName: "circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(UzumeAppColor.textDisabled)

            case .resolving, .downloading, .analyzing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: UzumeAppColor.textSecondary))
                    .scaleEffect(0.75)

            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(UzumeAppColor.success)

            case .partial:
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(UzumeAppColor.warning)

            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(UzumeAppColor.danger.opacity(0.8))
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}
