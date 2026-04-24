// TrackPreparationRow — Single row in the preparation progress list.
// Icon + title/artist/stage caption + optional progress sub-bar + optional ETA.

import Session
import SwiftUI

// MARK: - TrackPreparationRow

/// One row in `PreparationProgressView`'s track list.
///
/// Displays the track's current status with an icon, a stage caption, a progress
/// sub-bar for `.downloading` with known progress, and an ETA estimate when
/// sufficient historical data is available.
struct TrackPreparationRow: View {

    let row: RowData

    var body: some View {
        HStack(spacing: 12) {
            TrackPreparationStatusIcon(status: row.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(row.artist)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                Text(stageCaption)
                    .font(.caption2)
                    .foregroundColor(stageCaptionColor)

                if case .downloading(let progress) = row.status, progress >= 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.6)))
                        .frame(height: 2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if let eta = row.etaSeconds, row.status.isInFlight {
                Text(etaText(eta))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Private

    private var stageCaption: String {
        switch row.status {
        case .queued:                          return "Waiting"
        case .resolving:                       return "Finding preview"
        case .downloading(let pct) where pct < 0: return "Downloading"
        case .downloading(let pct):               return "Downloading — \(Int(pct * 100))%"
        case .analyzing(let stage):
            switch stage {
            case .stemSeparation, .mir: return "Separating stems"
            case .caching:             return "Caching"
            }
        case .ready:                           return "Ready"
        case .partial(let reason):             return "Partial — \(reason)"
        case .failed(let reason):              return "Failed — \(reason)"
        }
    }

    private var stageCaptionColor: Color {
        switch row.status {
        case .ready:   return .green.opacity(0.8)
        case .partial: return .orange.opacity(0.8)
        case .failed:  return .red.opacity(0.7)
        default:       return .white.opacity(0.35)
        }
    }

    private var accessibilityLabel: String {
        "\(row.title) by \(row.artist). \(stageCaption)"
    }

    private var accessibilityValue: String {
        if case .downloading(let pct) = row.status, pct >= 0 {
            return "\(Int(pct * 100)) percent"
        }
        return ""
    }

    private func etaText(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "~\(Int(seconds))s"
        }
        return "~\(Int(seconds / 60))m"
    }
}
