// ShortcutHelpOverlayView — Full keyboard shortcut reference, shown on Shift+?.

import SwiftUI

// MARK: - ShortcutHelpOverlayView

/// Full-width overlay listing all in-session keyboard shortcuts.
///
/// Appears on `Shift+?`, dismisses on any key press via `onDismiss`.
/// Groups shortcuts by category (Playback / Live Adaptation / Developer).
struct ShortcutHelpOverlayView: View {

    static let accessibilityID = "phosphene.playback.shortcutHelp"

    let shortcuts: [PlaybackShortcut]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dismiss tap target (background)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "Keyboard shortcut help"]
            )
        }
    }

    // MARK: - Panel

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                ForEach(ShortcutCategory.allCases, id: \.self) { category in
                    let categoryShortcuts = shortcuts.filter { $0.category == category }
                    if !categoryShortcuts.isEmpty {
                        categorySection(category, shortcuts: categoryShortcuts)
                    }
                }

                Text("Press any key to dismiss")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(28)
        }
        .frame(maxWidth: 560)
        .background(.ultraThinMaterial)
        .overlay { Color.black.opacity(0.4) }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 40)
    }

    // MARK: - Category Section

    private func categorySection(_ category: ShortcutCategory, shortcuts: [PlaybackShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 2)

            ForEach(shortcuts, id: \.id) { shortcut in
                shortcutRow(shortcut)
            }
        }
    }

    // MARK: - Shortcut Row

    private func shortcutRow(_ shortcut: PlaybackShortcut) -> some View {
        HStack {
            Text(shortcut.label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(keyLabel(shortcut))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Key Label

    private func keyLabel(_ shortcut: PlaybackShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.command) { parts.append("⌘") }
        if shortcut.modifiers.contains(.shift) { parts.append("⇧") }
        if shortcut.modifiers.contains(.option) { parts.append("⌥") }
        if shortcut.modifiers.contains(.control) { parts.append("⌃") }

        let keyDisplay: String
        switch shortcut.key {
        case " ":        keyDisplay = "Space"
        case "\u{1B}":   keyDisplay = "Esc"
        case "\u{F703}": keyDisplay = "→"
        case "\u{F702}": keyDisplay = "←"
        default:         keyDisplay = shortcut.key.uppercased()
        }

        parts.append(keyDisplay)
        return parts.joined()
    }
}
