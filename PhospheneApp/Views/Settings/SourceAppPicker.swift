// SourceAppPicker — Lists running apps for audio capture source selection (U.8 Part B).

import AppKit
import SwiftUI

// MARK: - SourceAppPicker

/// Multi-row picker of running applications for the "Specific App" capture mode.
///
/// Shows all running applications with a bundle identifier. If the currently-selected
/// app is no longer running, its name is shown with a "(not running)" suffix.
struct SourceAppPicker: View {

    @Binding var selection: SourceAppOverride?
    @State private var runningApps: [RunningAppEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("settings.audio.source_app.label", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            List(displayedApps, id: \.bundleIdentifier, selection: $selection) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(app.label)
                        .foregroundColor(app.isRunning ? .primary : .secondary)
                }
                .tag(SourceAppOverride(
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.displayName
                ) as SourceAppOverride?)
            }
            .frame(height: 120)
            .border(Color.secondary.opacity(0.2), width: 1)
        }
        .onAppear { refreshApps() }
    }

    // MARK: - Private

    private var displayedApps: [RunningAppEntry] {
        var apps = runningApps
        // If the selected app isn't in running apps, prepend it as "(not running)"
        if let sel = selection,
           !apps.contains(where: { $0.bundleIdentifier == sel.bundleIdentifier }) {
            apps.insert(RunningAppEntry(
                bundleIdentifier: sel.bundleIdentifier,
                displayName: sel.displayName,
                icon: nil,
                isRunning: false
            ), at: 0)
        }
        return apps
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningAppEntry? in
                guard let id = app.bundleIdentifier,
                      let name = app.localizedName,
                      app.activationPolicy == .regular
                else { return nil }
                return RunningAppEntry(
                    bundleIdentifier: id,
                    displayName: name,
                    icon: app.icon,
                    isRunning: true
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}

// MARK: - RunningAppEntry

private struct RunningAppEntry: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage?
    let isRunning: Bool

    var id: String { bundleIdentifier }
    var label: String { isRunning ? displayName : "\(displayName) (not running)" }

    func hash(into hasher: inout Hasher) { hasher.combine(bundleIdentifier) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bundleIdentifier == rhs.bundleIdentifier }
}
