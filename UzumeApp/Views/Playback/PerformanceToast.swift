// PerformanceToast — the transient status placement. (DS.3)
//
// Everything about the placement is unchanged across the DS.3 rename: it queues up
// to three deep in `ToastRegion`, announces itself to VoiceOver on insert, carries an
// optional action button and a dismiss button, and `ToastManager` still owns the
// queue and the coalescing.
//
// DS.1 had already moved this off raw colours, so the change here is smaller than on
// the other three surfaces: the inline severity switch — the third of the app's three
// disagreeing maps — becomes a `StatusTone` lookup. It is the map that read
// `degradation` as red while the full-screen surfaces read it as yellow; under D-235
// both now read it as caution.
//
// This is the only placement that appears during a performance, so it stays the
// quietest thing that can still be noticed: a 4pt accent bar, no icon, no fill.
//
// BUG-113 (DS.6): the accent bar is a `Color`, which takes whatever height it is
// offered — and inside the chrome's full-height ZStack that offer is the whole
// window, so every toast rendered as a floor-to-ceiling panel over the cluster.
// `.fixedSize(vertical:)` makes the toast its copy's height wherever it is placed.

import SwiftUI

// MARK: - PerformanceToast

/// A single toast: tone accent bar + copy + optional action + dismiss.
struct PerformanceToast: View {

    let toast: UzumeToast
    let onDismiss: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            accentBar

            HStack(spacing: 8) {
                Text(toast.copy)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(UzumeAppColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if let action = toast.action {
                    Button(action.label) {
                        action.handler()
                        onDismiss(toast.id)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.foreground)
                    .buttonStyle(.plain)
                }

                Button {
                    onDismiss(toast.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(UzumeAppColor.textDisabled)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay { UzumeAppColor.Performance.toastTint }
        .clipShape(RoundedRectangle(cornerRadius: UzumeAppRadius.sm))
        .frame(maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)   // BUG-113
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AccessibilityLabels.toastLabel(copy: toast.copy, severity: toast.severity))
    }

    // MARK: - Helpers

    private var accentBar: some View {
        tone.foreground
            .frame(width: 4)
            .clipShape(
                RoundedRectangle(cornerRadius: UzumeAppRadius.sm)
                    .path(in: CGRect(x: 0, y: 0, width: 4, height: 100))
            )
    }

    private var tone: StatusTone { .from(toast.severity) }
}
