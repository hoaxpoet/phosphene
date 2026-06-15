// AudioSettingsSection — Audio capture settings (U.8 Part B).

import SwiftUI

// MARK: - AudioSettingsSection

struct AudioSettingsSection: View {

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.audio.capture_mode.label", comment: "")) {
                Picker(
                    NSLocalizedString("settings.audio.capture_mode.label", comment: ""),
                    selection: Binding(
                        get: { viewModel.captureMode },
                        set: { viewModel.captureMode = $0 }
                    )
                ) {
                    Text(NSLocalizedString("settings.audio.capture_mode.system", comment: ""))
                        .tag(CaptureMode.systemAudio)
                    Text(NSLocalizedString("settings.audio.capture_mode.specific_app", comment: ""))
                        .tag(CaptureMode.specificApp)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if viewModel.captureMode == .specificApp {
                    SourceAppPicker(
                        selection: Binding(
                            get: { viewModel.sourceAppOverride },
                            set: { viewModel.sourceAppOverride = $0 }
                        )
                    )
                    .padding(.top, 4)
                }
            }

            Section(NSLocalizedString("settings.audio.quality_hints.title", comment: "")) {
                Text(NSLocalizedString("settings.audio.quality_hints.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.audio", comment: ""))
    }
}
