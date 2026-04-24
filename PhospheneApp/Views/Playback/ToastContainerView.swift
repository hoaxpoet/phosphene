// ToastContainerView — Bottom-trailing stack of up to three toast notifications.

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
    }
}
