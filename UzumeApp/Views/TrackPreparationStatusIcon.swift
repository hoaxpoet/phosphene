// TrackPreparationStatusIcon — Small icon component for TrackPreparationRow.
// Spinner for in-flight statuses; SF Symbol for terminal states.

import Session
import SwiftUI

// MARK: - TrackPreparationStatusIcon

/// 28 × 28 pt icon representing a single track's preparation status.
///
/// In-flight statuses (`.resolving`, `.downloading`, `.analyzing`) render a
/// theme-coloured spinner. Terminal statuses render an SF Symbol.
struct TrackPreparationStatusIcon: View {
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
