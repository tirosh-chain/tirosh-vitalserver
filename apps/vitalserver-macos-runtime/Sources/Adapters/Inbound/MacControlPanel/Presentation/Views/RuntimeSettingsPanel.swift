import Foundation
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeSettingsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingApplySettingsConfirmation: Bool
    @Binding var showingRestartVMRuntimeConfirmation: Bool
    private let actionAvailabilityPolicy = RuntimeControlActionAvailabilityPolicy()
    private let restartNoticePolicy = RuntimeSettingsRestartNoticePolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsReadIssuesSection
                settingsSection(AppConstants.Labels.sectionVM) {
                    settingSlider(
                        AppConstants.Labels.cpu,
                        value: $viewModel.settings.cpuCount,
                        range: cpuCountRange,
                        suffix: AppConstants.Labels.unitVCPU
                    )
                    .disabled(!viewModel.capabilities.canEditVMResources)
                    settingSlider(
                        AppConstants.Labels.memory,
                        value: $viewModel.settings.memoryGiB,
                        range: memoryRange,
                        step: AppConstants.SettingsLimits.memoryStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!viewModel.capabilities.canEditVMResources)
                    settingHelp(AppConstants.Labels.memoryAllocationHelp)
                    settingSlider(
                        AppConstants.Labels.disk,
                        value: $viewModel.settings.diskGiB,
                        range: diskSizeRange,
                        step: AppConstants.SettingsLimits.diskStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!viewModel.capabilities.canEditVMResources)
                    settingWarning(AppConstants.Labels.diskIncreaseOnlyHelp(viewModel.settings.minimumDiskGiB))
                }
                settingsSection(AppConstants.Labels.sectionNetwork) {
                    settingRow(AppConstants.Labels.mode) {
                        networkModeSelector
                    }
                    settingHelp(networkModeHelp)
                    settingPortField(AppConstants.Labels.proxyPort, value: $viewModel.settings.proxyPort)
                        .disabled(!viewModel.capabilities.canEditNetworkExposure)
                    settingHelp(AppConstants.Labels.proxyPortHelp)
                    settingPortField(AppConstants.Labels.runtimeControlPort, value: $viewModel.settings.runtimeControlPort)
                        .disabled(!viewModel.capabilities.canEditNetworkExposure)
                    settingHelp(AppConstants.Labels.runtimeControlPortHelp)
                }
                settingsSection(AppConstants.Labels.sectionStorage) {
                    settingDirectoryField(
                        AppConstants.Labels.vitalFilesDirectory,
                        text: $viewModel.settings.vitalFilesDirectory
                    )
                }
                settingsSection(AppConstants.Labels.sectionRedisData) {
                    settingRow(AppConstants.Labels.redisBackupRetention) {
                        HStack(spacing: 12) {
                            settingSliderControl(
                                value: $viewModel.settings.redisBackupRetentionCount,
                                range: AppConstants.SettingsLimits.minimumRedisBackupRetentionCount...AppConstants.SettingsLimits.maximumRedisBackupRetentionCount,
                                step: AppConstants.SettingsLimits.redisBackupRetentionStep,
                                suffix: "archives"
                            )
                            Button(AppConstants.Actions.openBackups) {
                                viewModel.openRedisBackups()
                            }
                            .disabled(!viewModel.capabilities.canOpenLocalFiles)
                        }
                    }
                    settingHelp(AppConstants.Labels.redisBackupRetentionHelp)
                }
                settingsSection(AppConstants.Labels.sectionOperations) {
                    settingToggle(AppConstants.Labels.startOnBoot, isOn: $viewModel.settings.startOnBoot)
                        .disabled(
                            !viewModel.settings.startOnBootConfigurable
                                || !viewModel.capabilities.canControlRuntimeServices
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        settingToggle(AppConstants.Labels.automaticRecovery, isOn: $viewModel.settings.autoRecoveryEnabled)
                            .disabled(!viewModel.capabilities.canControlRuntimeServices)
                        settingHelp(AppConstants.Labels.automaticRecoveryHelp)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        settingToggle(AppConstants.Labels.preventSystemSleep, isOn: $viewModel.settings.preventSystemSleep)
                            .disabled(!viewModel.capabilities.canControlRuntimeServices)
                        settingHelp(AppConstants.Labels.preventSystemSleepHelp)
                    }
                }
                restartRuntimeSection
                applyActionRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
        .onAppear {
            clampCPUCountToSystemLimit()
            clampMemoryToSystemLimit()
        }
        .onChange(of: viewModel.settings.cpuCount) {
            clampCPUCountToSystemLimit()
        }
        .onChange(of: viewModel.settings.memoryGiB) {
            clampMemoryToSystemLimit()
        }
        .onChange(of: viewModel.settings.proxyPort) {
            viewModel.syncAdvertisedURLWithProxyIfNeeded()
        }
        .onChange(of: viewModel.settings.runtimeControlPort) {
            viewModel.syncAdvertisedURLWithProxyIfNeeded()
        }
    }

    @ViewBuilder
    private var settingsReadIssuesSection: some View {
        if !viewModel.settings.readIssues.isEmpty {
            settingsSection(AppConstants.Labels.settingsReadIssues) {
                ForEach(viewModel.settings.readIssues, id: \.source) { issue in
                    Text("\(issue.source): \(issue.message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
        viewModel.settings.networkMode == RuntimeNetworkMode.shared
            ? AppConstants.Labels.sharedNetworkHelp
            : AppConstants.Labels.bridgedNetworkHelp
    }

    private var diskSizeRange: ClosedRange<Int> {
        let minimum = viewModel.settings.minimumDiskGiB
        return minimum...max(minimum, AppConstants.SettingsLimits.maximumDiskGiB)
    }

    private var cpuCountRange: ClosedRange<Int> {
        let minimum = AppConstants.SettingsLimits.minimumCPUCount
        return minimum...AppConstants.SettingsLimits.maximumAllowedCPUCount
    }

    private var memoryRange: ClosedRange<Int> {
        let minimum = AppConstants.SettingsLimits.minimumMemoryGiB
        return minimum...AppConstants.SettingsLimits.maximumAllowedMemoryGiB
    }

    private var canApplySettingsForCurrentConnection: Bool {
        viewModel.capabilities.canEditVMResources
            || viewModel.capabilities.canEditNetworkExposure
            || viewModel.capabilities.canOpenLocalFiles
            || viewModel.capabilities.canResetAdminPassword
            || viewModel.capabilities.canControlRuntimeServices
    }

    private var restartNotice: RuntimeSettingsRestartNoticeDecision {
        restartNoticePolicy.decision(draft: viewModel.settings, runtime: viewModel.runtimeSettings)
    }

    private var restartRuntimeSection: some View {
        settingsSection(AppConstants.Labels.vmRuntimeRestart) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(restartNotice.message)
                        .font(.caption)
                        .foregroundStyle(restartNotice.requiresRestart ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    let savedNotice = restartNoticePolicy.decision(
                        draft: viewModel.savedSettings,
                        runtime: viewModel.runtimeSettings
                    )
                    if savedNotice.requiresRestart && savedNotice.message != restartNotice.message {
                        Text(savedNotice.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                restartRequirementBadge
            }
        }
    }

    private var restartRequirementBadge: some View {
        let savedNotice = restartNoticePolicy.decision(
            draft: viewModel.savedSettings,
            runtime: viewModel.runtimeSettings
        )
        let requiresRestart = restartNotice.requiresRestart || savedNotice.requiresRestart
        return Button {
            showingRestartVMRuntimeConfirmation = true
        } label: {
            Label(
                requiresRestart
                    ? AppConstants.Labels.requiresVMRestart
                    : AppConstants.StatusText.noVMRuntimeRestartRequired,
                systemImage: requiresRestart
                    ? "arrow.clockwise.circle.fill"
                    : "checkmark.circle.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(requiresRestart ? .orange : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((requiresRestart ? Color.orange : Color.secondary).opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke((requiresRestart ? Color.orange : Color.secondary).opacity(0.35), lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(
            !requiresRestart
                || !viewModel.capabilities.canControlRuntimeServices
                || viewModel.isBusy
        )
        .help(requiresRestart ? AppConstants.StatusText.restartVMRuntimeConfirmation : restartNotice.message)
    }

    private var applyActionRow: some View {
        HStack(spacing: 12) {
            Button(AppConstants.Actions.applySettings) {
                if viewModel.prepareApplySettings() {
                    showingApplySettingsConfirmation = true
                }
            }
            .disabled(!actionAvailabilityPolicy.canApplySettings(
                status: viewModel.status,
                isBusy: viewModel.isBusy,
                canApplyForCurrentConnection: canApplySettingsForCurrentConnection
            ))

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let validationMessage = viewModel.settingsValidationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func clampCPUCountToSystemLimit() {
        let clampedCPUCount = min(max(viewModel.settings.cpuCount, cpuCountRange.lowerBound), cpuCountRange.upperBound)
        if viewModel.settings.cpuCount != clampedCPUCount {
            viewModel.settings.cpuCount = clampedCPUCount
        }
    }

    private func clampMemoryToSystemLimit() {
        let clampedMemoryGiB = min(max(viewModel.settings.memoryGiB, memoryRange.lowerBound), memoryRange.upperBound)
        if viewModel.settings.memoryGiB != clampedMemoryGiB {
            viewModel.settings.memoryGiB = clampedMemoryGiB
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
            settingSliderControl(value: value, range: range, step: step, suffix: suffix)
        }
    }

    private func settingSliderControl(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = ""
    ) -> some View {
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

    private func settingDirectoryField(
        _ label: String,
        text: Binding<String>
    ) -> some View {
        settingRow(label) {
            HStack(spacing: 8) {
                TextField("", text: text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 440)
                    .disabled(!viewModel.capabilities.canOpenLocalFiles)
                Button(AppConstants.Actions.chooseDirectory) {
                    viewModel.chooseVitalFilesDirectory()
                }
                .disabled(viewModel.isBusy || !viewModel.capabilities.canOpenLocalFiles)
            }
        }
    }

    private func settingPortField(_ label: String, value: Binding<Int>) -> some View {
        settingRow(label) {
            TextField("", value: value, formatter: portNumberFormatter)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        settingRow(label) {
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private var portNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 65_535
        formatter.allowsFloats = false
        return formatter
    }
}
