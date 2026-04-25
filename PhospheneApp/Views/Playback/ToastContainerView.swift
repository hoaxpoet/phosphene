// ToastContainerView — Bottom-trailing stack of up to three toast notifications.

import Accessibility
import SwiftUI

// MARK: - ToastContainerView

/// Stacks `ToastView` cells for all currently-visible toasts.
///
/// Uses `.transition(.move(edge: .trailing).combined(with: .opacity))`.
/// Placed bottom-trailing in `PlaybackChromeView`.
struct ToastContainerView: View {

    @ObservedObject var toastManager: ToastManager

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(toastManager.visibleToasts) { toast in
                ToastView(toast: toast) { id in
                    toastManager.dismiss(id: id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastManager.visibleToasts.map(\.id))
        .allowsHitTesting(!toastManager.visibleToasts.isEmpty)
        .onChange(of: toastManager.visibleToasts) { oldToasts, newToasts in
            let added = newToasts.filter { new in !oldToasts.contains(where: { $0.id == new.id }) }
            for toast in added {
                let label = AccessibilityLabels.toastLabel(copy: toast.copy, severity: toast.severity)
                AccessibilityNotification.Announcement(label).post()
            }
        }
    }
}
