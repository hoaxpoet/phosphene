// PlanPreviewRowView — One track row in the plan preview panel (U.5 Part B).

import Orchestrator
import Presets
import Session
import SwiftUI

// MARK: - PlanPreviewRowView

/// Displays one `PlanPreviewRow`: track number + title + artist + preset + family pill + duration.
///
/// A lock icon appears on locked rows. Long-press / right-click shows a "Reset to planner
/// pick" item; the "Swap preset" action is hidden behind `ENABLE_PRESET_SWAP` until U.5b.
struct PlanPreviewRowView: View {

    let row: PlanPreviewRow
    let catalog: [PresetDescriptor]
    let onSwap: (TrackIdentity, PresetDescriptor) -> Void
    let onResetLock: (TrackIdentity) -> Void
    let onPreview: (PlanPreviewRow) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Track number
            Text("\(row.trackIndex + 1)")
                .font(.footnote.monospaced())
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 28, alignment: .trailing)

            // Lock icon
            if row.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow.opacity(0.7))
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }

            // Track title + artist
            VStack(alignment: .leading, spacing: 2) {
                Text(row.trackTitle)
                    .font(.callout.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !row.trackArtist.isEmpty {
                    Text(row.trackArtist)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Preset name + family pill
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.presetName)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                Text(row.presetFamily)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            // Duration
            Text(formattedDuration)
                .font(.caption.monospaced())
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(row.isLocked ? Color.yellow.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onPreview(row) }
        .contextMenu {
            // QR.4 / D-091 honest-UI: the disabled "Swap preset" stub is a dead control
            // until U.5b's preview loop lands — hide it behind a build flag (mirrors the
            // ENABLE_PLAN_MODIFICATION-gated Modify button in PlanPreviewView) rather than
            // shipping a greyed, do-nothing item. onSwap / swapPreset plumbing stays intact.
            #if ENABLE_PRESET_SWAP
            // TODO(U.5b): wire to onSwap(row.id, …) when the preview loop can host the swap UI.
            Button(String(localized: "plan_preview.row.swap_preset")) {}
                .disabled(true)
            #endif

            if row.isLocked {
                Button(String(localized: "plan_preview.row.reset_lock")) {
                    onResetLock(row.id)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(format: String(localized: "plan_preview.row.accessibility"),
                   row.trackIndex + 1,
                   row.trackTitle,
                   row.trackArtist,
                   row.presetName,
                   formattedDuration)
        )
    }

    private var formattedDuration: String {
        let mins = Int(row.duration) / 60
        let secs = Int(row.duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
