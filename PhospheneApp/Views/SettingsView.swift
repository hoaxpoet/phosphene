// SettingsView — Settings sheet: Local Files, Visuals, Diagnostics, About.
// Full implementation in U.8 Part B. (The Audio tab was removed in CLEAN.2.3.8
// once the per-app-capture picker was deleted — System audio is the only source,
// so the screen had no controls left; rebuild a source picker if one is added back.)

import SwiftUI

// MARK: - SettingsView

/// Preferences-style sheet. NavigationSplitView sidebar + detail.
struct SettingsView: View {

    static let accessibilityID = "phosphene.view.settings"

    @StateObject private var viewModel: SettingsViewModel
    @State private var selection: SettingsSection? = .localFiles
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(store: store))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, id: \.self, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            Group {
                switch selection ?? .localFiles {
                case .localFiles:  LocalFilesSettingsSection()
                case .visuals:     VisualsSettingsSection(viewModel: viewModel)
                case .diagnostics: DiagnosticsSettingsSection(viewModel: viewModel)
                case .about:       AboutSettingsSection(viewModel: viewModel)
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
        .frame(width: 720, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("settings.done_button", comment: "")) { dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onExitCommand { dismiss() }
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// MARK: - SettingsSection

enum SettingsSection: String, CaseIterable, Identifiable {
    case localFiles, visuals, diagnostics, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .localFiles:  return NSLocalizedString("settings.group.local_files", comment: "")
        case .visuals:     return NSLocalizedString("settings.group.visuals", comment: "")
        case .diagnostics: return NSLocalizedString("settings.group.diagnostics", comment: "")
        case .about:       return NSLocalizedString("settings.group.about", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .localFiles:  return "folder"
        case .visuals:     return "eye"
        case .diagnostics: return "stethoscope"
        case .about:       return "info.circle"
        }
    }
}
