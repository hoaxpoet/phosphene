// ToastRegion — bottom-trailing stack of up to three `PerformanceToast` cells. (DS.3)
//
// Renamed at DS.3; behaviour is untouched. `ToastManager` owns how many are visible
// and which are dropped — this only lays them out, animates the trailing move, and
// posts the VoiceOver announcement when one is inserted. DS.6: the move takes the
// standard state-change motion, and under reduced motion it is a crossfade, not a slide.

import Accessibility
import SwiftUI

// MARK: - ToastRegion

/// Stacks the currently-visible toasts bottom-trailing in `PlaybackChromeView`.
struct ToastRegion: View {

    @ObservedObject var toastManager: ToastManager
    var reduceMotion: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: UzumeSpace.x2) {
            ForEach(toastManager.visibleToasts) { toast in
                PerformanceToast(toast: toast) { id in
                    toastManager.dismiss(id: id)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(UzumeAppMotion.stateChange(reduceMotion: reduceMotion), value: toastManager.visibleToasts.map(\.id))
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
