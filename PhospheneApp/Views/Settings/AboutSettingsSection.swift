// AboutSettingsSection — App version, license, and debug info (U.8 Part B).

import SwiftUI

// MARK: - AboutSettingsSection

struct AboutSettingsSection: View {

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.about.app.title", comment: "")) {
                LabeledContent(
                    NSLocalizedString("settings.about.version.label", comment: ""),
                    value: "\(viewModel.about.appVersion) (\(viewModel.about.buildNumber))"
                )
                LabeledContent(
                    NSLocalizedString("settings.about.macos.label", comment: ""),
                    value: viewModel.about.macOSVersion
                )
                LabeledContent(
                    NSLocalizedString("settings.about.gpu.label", comment: ""),
                    value: viewModel.about.gpuFamily
                )
            }

            Section(NSLocalizedString("settings.about.license.title", comment: "")) {
                Text(NSLocalizedString("settings.about.license.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(NSLocalizedString("settings.about.copy_debug_info", comment: "")) {
                    viewModel.copyDebugInfo()
                }
                Text(NSLocalizedString("settings.about.copy_debug_info.caption", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.about", comment: ""))
    }
}
