import Management
import SwiftUI

struct RuntimeSettingsPanel: View {
    @ObservedObject var controller: RuntimeController
    @Binding var showingApplySettingsConfirmation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(AppConstants.Labels.sectionVM) {
                    settingSlider(
                        AppConstants.Labels.cpu,
                        value: $controller.settings.cpuCount,
                        range: AppConstants.SettingsLimits.minimumCPUCount...AppConstants.SettingsLimits.maximumCPUCount,
                        suffix: AppConstants.Labels.unitVCPU
                    )
                    .disabled(!controller.capabilities.canEditVMResources)
                    settingSlider(
                        AppConstants.Labels.memory,
                        value: $controller.settings.memoryGiB,
                        range: AppConstants.SettingsLimits.minimumMemoryGiB...AppConstants.SettingsLimits.maximumMemoryGiB,
                        step: AppConstants.SettingsLimits.memoryStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!controller.capabilities.canEditVMResources)
                    settingHelp(AppConstants.Labels.memoryAllocationHelp)
                    settingSlider(
                        AppConstants.Labels.disk,
                        value: $controller.settings.diskGiB,
                        range: diskSizeRange,
                        step: AppConstants.SettingsLimits.diskStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!controller.capabilities.canEditVMResources)
                    settingWarning(AppConstants.Labels.diskIncreaseOnlyHelp(controller.settings.minimumDiskGiB))
                }
                settingsSection(AppConstants.Labels.sectionNetwork) {
                    settingRow(AppConstants.Labels.mode) {
                        networkModeSelector
                    }
                    settingHelp(networkModeHelp)
                }
                settingsSection(AppConstants.Labels.sectionStorage) {
                    settingDirectoryField(AppConstants.Labels.vitalFilesDirectory, text: $controller.settings.vitalFilesDirectory)
                }
                settingsSection(AppConstants.Labels.sectionOperations) {
                    settingToggle(AppConstants.Labels.startOnBoot, isOn: $controller.settings.startOnBoot)
                        .disabled(
                            !controller.settings.startOnBootConfigurable
                                || !controller.capabilities.canControlRuntimeServices
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        settingToggle(AppConstants.Labels.automaticRecovery, isOn: $controller.settings.autoRecoveryEnabled)
                            .disabled(!controller.capabilities.canControlRuntimeServices)
                        settingHelp(AppConstants.Labels.automaticRecoveryHelp)
                    }
                    settingToggle(AppConstants.Labels.restartServicesAfterSave, isOn: $controller.settings.restartAfterSave)
                        .disabled(!controller.capabilities.canControlRuntimeServices)
                }
                applyActionRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
    }

    private var networkModeSelector: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.shared)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(AppConstants.Labels.bridgedUnavailable)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var networkModeHelp: String {
        controller.settings.networkMode == RuntimeNetworkMode.shared
            ? AppConstants.Labels.sharedNetworkHelp
            : AppConstants.Labels.bridgedNetworkHelp
    }

    private var diskSizeRange: ClosedRange<Int> {
        let minimum = controller.settings.minimumDiskGiB
        return minimum...max(minimum, AppConstants.SettingsLimits.maximumDiskGiB)
    }

    private var canApplySettingsForCurrentConnection: Bool {
        controller.capabilities.canEditVMResources
            || controller.capabilities.canEditNetworkExposure
            || controller.capabilities.canOpenLocalFiles
            || controller.capabilities.canResetAdminPassword
    }

    private var applyActionRow: some View {
        HStack(spacing: 12) {
            Button(AppConstants.Actions.applySettings) {
                if controller.prepareApplySettings() {
                    showingApplySettingsConfirmation = true
                }
            }
            .disabled(controller.isBusy || !controller.status.runtimeInstalled || !canApplySettingsForCurrentConnection)

            if controller.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(controller.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func settingHelp(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 174)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingWarning(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.leading, 174)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func settingSlider(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = ""
    ) -> some View {
        settingRow(label) {
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .frame(width: 260)
                Text(suffix.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(suffix)")
                    .fontWeight(.medium)
                    .frame(width: 90, alignment: .leading)
            }
        }
    }

    private func settingDirectoryField(_ label: String, text: Binding<String>) -> some View {
        settingRow(label) {
            HStack(spacing: 8) {
                TextField("", text: text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 440)
                    .disabled(!controller.capabilities.canOpenLocalFiles)
                Button(AppConstants.Actions.chooseDirectory) {
                    controller.chooseVitalFilesDirectory()
                }
                .disabled(controller.isBusy || !controller.capabilities.canOpenLocalFiles)
            }
        }
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        settingRow(label) {
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }
}
