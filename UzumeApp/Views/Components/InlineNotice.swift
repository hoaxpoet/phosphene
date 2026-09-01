// InlineNotice — the quietest status placement. (DS.3)
//
// Its predecessor lived inside `LocalFileErrorStore.swift`. A view has no business
// in a store file; the store keeps its `@Published` error and its 6-second
// auto-clear task, and this renders it.
//
// Deliberately has no background and no border. The other three placements announce
// themselves; this one sits inside an existing pane (IdleView, LocalSourceConnectionView)
// and only needs to read as an error message rather than decorative text. It takes the
// tone's foreground for its pip and nothing else from the triple — the absence of a
// field is the point of this placement, per COMPONENTS.md § Status placements.
//
// Lifetime and dismissal are unchanged: the store clears itself after six seconds,
// and tapping anywhere on the notice clears it early.

import SwiftUI

// MARK: - InlineNotice

/// Inline, background-less error line with a small tone pip. Tap to dismiss.
struct InlineNotice: View {

    let message: String
    let tone: StatusTone
    let onDismiss: () -> Void

    init(message: String, tone: StatusTone = .danger, onDismiss: @escaping () -> Void) {
        self.message = message
        self.tone = tone
        self.onDismiss = onDismiss
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tone.foreground)
                    .frame(width: 6, height: 6)
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundColor(UzumeAppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}
