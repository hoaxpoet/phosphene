// ToastView — Individual toast notification cell.

import SwiftUI

// MARK: - ToastView

/// Renders a single `UzumeToast` with severity accent bar + copy + optional action.
struct ToastView: View {

    let toast: UzumeToast
    let onDismiss: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Severity accent bar
            accentBar

            // Copy + action
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
                    .foregroundColor(accentColor)
                    .buttonStyle(.plain)
                }

                // Dismiss button
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AccessibilityLabels.toastLabel(copy: toast.copy, severity: toast.severity))
    }

    // MARK: - Helpers

    private var accentBar: some View {
        accentColor
            .frame(width: 4)
            .clipShape(
                RoundedRectangle(cornerRadius: UzumeAppRadius.sm)
                    .path(in: CGRect(x: 0, y: 0, width: 4, height: 100))
            )
    }

    private var accentColor: Color {
        switch toast.severity {
        case .info:        return UzumeAppColor.Status.infoForeground
        case .warning:     return UzumeAppColor.Status.warningForeground
        case .degradation: return UzumeAppColor.Status.dangerForeground
        }
    }
}
