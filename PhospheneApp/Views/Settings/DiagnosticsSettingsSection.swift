// DiagnosticsSettingsSection — Session recording and diagnostic settings (U.8 Part B).

import SwiftUI

// MARK: - DiagnosticsSettingsSection

struct DiagnosticsSettingsSection: View {

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.diagnostics.recorder.title", comment: "")) {
                Toggle(
                    NSLocalizedString("settings.diagnostics.recorder.label", comment: ""),
                    isOn: Binding(
                        get: { viewModel.sessionRecorderEnabled },
                        set: { viewModel.sessionRecorderEnabled = $0 }
                    )
                )
                Text(NSLocalizedString("settings.diagnostics.recorder.caption", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(
                    NSLocalizedString("settings.diagnostics.retention.label", comment: ""),
                    selection: Binding(
                        get: { viewModel.sessionRetention },
                        set: { viewModel.sessionRetention = $0 }
                    )
                ) {
                    Text(NSLocalizedString("settings.diagnostics.retention.last10", comment: ""))
                        .tag(SessionRetentionPolicy.lastN10)
                    Text(NSLocalizedString("settings.diagnostics.retention.last25", comment: ""))
                        .tag(SessionRetentionPolicy.lastN25)
                    Text(NSLocalizedString("settings.diagnostics.retention.keep_all", comment: ""))
                        .tag(SessionRetentionPolicy.keepAll)
                    Text(NSLocalizedString("settings.diagnostics.retention.one_day", comment: ""))
                        .tag(SessionRetentionPolicy.oneDay)
                    Text(NSLocalizedString("settings.diagnostics.retention.one_week", comment: ""))
                        .tag(SessionRetentionPolicy.oneWeek)
                }
            }

            // showPerformanceWarnings deleted in QR.4 / D-091: setting was never
            // wired to a consumer. The dashboard PERF card already surfaces
            // frame-budget overruns; a separate toast surface was redundant.

            Section {
                Button(NSLocalizedString("settings.diagnostics.open_sessions_folder", comment: "")) {
                    viewModel.openSessionsFolder()
                }

                Button(NSLocalizedString("settings.diagnostics.reset_onboarding", comment: ""), role: .destructive) {
                    viewModel.resetOnboarding()
                }
                Text(NSLocalizedString("settings.diagnostics.reset_onboarding.caption", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.diagnostics", comment: ""))
    }
}
