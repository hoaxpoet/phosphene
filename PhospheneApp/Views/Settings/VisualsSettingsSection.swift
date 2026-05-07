// VisualsSettingsSection — Visual quality and preset settings (U.8 Part B).

import Orchestrator
import Presets
import Shared
import SwiftUI

// MARK: - VisualsSettingsSection

struct VisualsSettingsSection: View {

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.visuals.device_tier.label", comment: "")) {
                Picker(
                    NSLocalizedString("settings.visuals.device_tier.label", comment: ""),
                    selection: Binding(
                        get: { viewModel.deviceTierOverride },
                        set: { viewModel.deviceTierOverride = $0 }
                    )
                ) {
                    Text(NSLocalizedString("settings.visuals.device_tier.auto", comment: ""))
                        .tag(DeviceTierOverride.auto)
                    Text(NSLocalizedString("settings.visuals.device_tier.tier1", comment: ""))
                        .tag(DeviceTierOverride.forceTier1)
                    Text(NSLocalizedString("settings.visuals.device_tier.tier2", comment: ""))
                        .tag(DeviceTierOverride.forceTier2)
                }
                .labelsHidden()

                Picker(
                    NSLocalizedString("settings.visuals.quality_ceiling.label", comment: ""),
                    selection: Binding(
                        get: { viewModel.qualityCeiling },
                        set: { viewModel.qualityCeiling = $0 }
                    )
                ) {
                    Text(NSLocalizedString("settings.visuals.quality_ceiling.auto", comment: ""))
                        .tag(QualityCeiling.auto)
                    Text(NSLocalizedString("settings.visuals.quality_ceiling.performance", comment: ""))
                        .tag(QualityCeiling.performance)
                    Text(NSLocalizedString("settings.visuals.quality_ceiling.balanced", comment: ""))
                        .tag(QualityCeiling.balanced)
                    Text(NSLocalizedString("settings.visuals.quality_ceiling.ultra", comment: ""))
                        .tag(QualityCeiling.ultra)
                }
            }

            Section(NSLocalizedString("settings.visuals.presets.title", comment: "")) {
                #if DEBUG
                // QR.4 / D-091: gated behind #if DEBUG until Phase MD ships.
                // Persistence is retained in SettingsStore so debug round-trips
                // preserve user state; production builds never see the toggle.
                Toggle(
                    NSLocalizedString("settings.visuals.milkdrop.label", comment: ""),
                    isOn: Binding(
                        get: { viewModel.includeMilkdropPresets },
                        set: { viewModel.includeMilkdropPresets = $0 }
                    )
                )
                .disabled(viewModel.includeMilkdropPresetsDisabled)

                if viewModel.includeMilkdropPresetsDisabled {
                    Text(NSLocalizedString("settings.visuals.milkdrop.coming_soon", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif

                Picker(
                    NSLocalizedString("settings.visuals.reduced_motion.label", comment: ""),
                    selection: Binding(
                        get: { viewModel.reducedMotion },
                        set: { viewModel.reducedMotion = $0 }
                    )
                ) {
                    Text(NSLocalizedString("settings.visuals.reduced_motion.match_system", comment: ""))
                        .tag(ReducedMotionPreference.matchSystem)
                    Text(NSLocalizedString("settings.visuals.reduced_motion.always_on", comment: ""))
                        .tag(ReducedMotionPreference.alwaysOn)
                    Text(NSLocalizedString("settings.visuals.reduced_motion.always_off", comment: ""))
                        .tag(ReducedMotionPreference.alwaysOff)
                }
            }

            Section(NSLocalizedString("settings.visuals.blocklist.title", comment: "")) {
                PresetCategoryBlocklistPicker(
                    selection: Binding(
                        get: { viewModel.excludedPresetCategories },
                        set: { viewModel.excludedPresetCategories = $0 }
                    )
                )
            }

            Section(NSLocalizedString("settings.visuals.toasts.title", comment: "")) {
                Toggle(
                    NSLocalizedString("settings.visuals.adaptation_toasts.label", comment: ""),
                    isOn: Binding(
                        get: { viewModel.showLiveAdaptationToasts },
                        set: { viewModel.showLiveAdaptationToasts = $0 }
                    )
                )
            }

            Section(NSLocalizedString("settings.visuals.certification.title", comment: "")) {
                Toggle(
                    NSLocalizedString("settings.visuals.show_uncertified_presets.label", comment: ""),
                    isOn: Binding(
                        get: { viewModel.showUncertifiedPresets },
                        set: { viewModel.showUncertifiedPresets = $0 }
                    )
                )
                .accessibilityLabel(
                    NSLocalizedString("settings.visuals.show_uncertified_presets.accessibility", comment: "")
                )
                Text(NSLocalizedString("settings.visuals.show_uncertified_presets.hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.visuals", comment: ""))
    }
}
