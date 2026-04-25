// ToastView — Individual toast notification cell.

import SwiftUI

// MARK: - ToastView

/// Renders a single `PhospheneToast` with severity accent bar + copy + optional action.
struct ToastView: View {

    let toast: PhospheneToast
    let onDismiss: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Severity accent bar
            accentBar

            // Copy + action
            HStack(spacing: 8) {
                Text(toast.copy)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
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
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay { Color.black.opacity(0.35) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AccessibilityLabels.toastLabel(copy: toast.copy, severity: toast.severity))
    }

    // MARK: - Helpers

    private var accentBar: some View {
        accentColor
            .frame(width: 4)
            .clipShape(RoundedRectangle(cornerRadius: 8).path(in: CGRect(x: 0, y: 0, width: 4, height: 100)))
    }

    private var accentColor: Color {
        switch toast.severity {
        case .info:        return .gray
        case .warning:     return .orange
        case .degradation: return .red
        }
    }
}
