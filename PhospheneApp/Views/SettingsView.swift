// SettingsView — Settings sheet with four sections: Audio, Visuals, Diagnostics, About.
// Full implementation in U.8 Part B.

import SwiftUI

// MARK: - SettingsView

/// Preferences-style sheet. NavigationSplitView sidebar + detail.
struct SettingsView: View {

    static let accessibilityID = "phosphene.view.settings"

    @StateObject private var viewModel: SettingsViewModel
    @State private var selection: SettingsSection? = .audio

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
                switch selection ?? .audio {
                case .audio:       AudioSettingsSection(viewModel: viewModel)
                case .visuals:     VisualsSettingsSection(viewModel: viewModel)
                case .diagnostics: DiagnosticsSettingsSection(viewModel: viewModel)
                case .about:       AboutSettingsSection(viewModel: viewModel)
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
        .frame(width: 720, height: 520)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// MARK: - SettingsSection

enum SettingsSection: String, CaseIterable, Identifiable {
    case audio, visuals, diagnostics, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio:       return NSLocalizedString("settings.group.audio", comment: "")
        case .visuals:     return NSLocalizedString("settings.group.visuals", comment: "")
        case .diagnostics: return NSLocalizedString("settings.group.diagnostics", comment: "")
        case .about:       return NSLocalizedString("settings.group.about", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .audio:       return "waveform"
        case .visuals:     return "eye"
        case .diagnostics: return "stethoscope"
        case .about:       return "info.circle"
        }
    }
}
