import Foundation
import Contracts
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeSettingsPanel: View {
    private enum ContainerMemoryLimitTarget {
        case vitalServer
        case recorderIngress
        case redis
    }

    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingApplySettingsConfirmation: Bool
    @Binding var showingRestartVMRuntimeConfirmation: Bool
    private let actionAvailabilityPolicy = RuntimeControlActionAvailabilityPolicy()
    private let restartNoticePolicy = RuntimeSettingsRestartNoticePolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsReadIssuesSection
                if viewModel.canDisplayPlatformSettings {
                    settingsSection(AppConstants.Labels.sectionVM) {
                    settingSlider(
                        AppConstants.Labels.cpu,
                        value: $viewModel.settings.cpuCount,
                        range: cpuCountRange,
                        suffix: AppConstants.Labels.unitVCPU
                    )
                    .disabled(!viewModel.capabilities.canEditRuntimeProviderResources)
                    settingSlider(
                        AppConstants.Labels.memory,
                        value: $viewModel.settings.memoryGiB,
                        range: memoryRange,
                        step: AppConstants.SettingsLimits.memoryStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!viewModel.capabilities.canEditRuntimeProviderResources)
                    settingHelp(AppConstants.Labels.memoryAllocationHelp)
                    settingSlider(
                        AppConstants.Labels.disk,
                        value: $viewModel.settings.diskGiB,
                        range: diskSizeRange,
                        step: AppConstants.SettingsLimits.diskStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    .disabled(!viewModel.capabilities.canEditRuntimeProviderResources)
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
                    settingToggle(AppConstants.Labels.recorderIngressLoadControl, isOn: recorderLoadControlBinding)
                    .disabled(!viewModel.capabilities.canControlRuntimeServices)
                    settingHelp(AppConstants.Labels.recorderIngressLoadControlHelp)
                    settingWarning(AppConstants.Labels.recorderIngressLoadControlRisk)
                    settingSlider(
                        AppConstants.Labels.recorderIngressMaxReplayThroughput,
                        value: $viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond,
                        range: AppConstants.SettingsLimits.minimumRecorderIngressReplayMaxMiBPerSecond...AppConstants.SettingsLimits.maximumRecorderIngressReplayMaxMiBPerSecond,
                        step: 1,
                        suffix: AppConstants.Labels.unitMiBPerSecond
                    )
                    .disabled(!viewModel.capabilities.canControlRuntimeServices || !recorderLoadControlEnabled)
                    settingHelp(AppConstants.Labels.recorderIngressReplayThroughputHelp)
                    containerMemoryLimitsToggleRow
                        .disabled(!viewModel.capabilities.canControlRuntimeServices)
                    settingHelp(AppConstants.Labels.containerMemoryLimitsHelp)
                    containerMemoryLimitSlider(
                        AppConstants.Labels.vitalServerContainerMemoryLimit,
                        target: .vitalServer,
                        value: $viewModel.settings.vitalServerContainerMemoryLimitMiB,
                        minimumMiB: AppConstants.SettingsLimits.minimumVitalServerContainerMemoryLimitMiB,
                        maximumMiB: AppConstants.SettingsLimits.maximumVitalServerContainerMemoryLimitMiB
                    )
                    .disabled(!viewModel.capabilities.canControlRuntimeServices || !viewModel.settings.containerMemoryLimitsEnabled)
                    containerMemoryLimitSlider(
                        AppConstants.Labels.recorderIngressContainerMemoryLimit,
                        target: .recorderIngress,
                        value: $viewModel.settings.recorderIngressContainerMemoryLimitMiB,
                        minimumMiB: AppConstants.SettingsLimits.minimumRecorderIngressContainerMemoryLimitMiB,
                        maximumMiB: AppConstants.SettingsLimits.maximumRecorderIngressContainerMemoryLimitMiB
                    )
                    .disabled(!viewModel.capabilities.canControlRuntimeServices || !viewModel.settings.containerMemoryLimitsEnabled)
                    containerMemoryLimitSlider(
                        AppConstants.Labels.redisContainerMemoryLimit,
                        target: .redis,
                        value: $viewModel.settings.redisContainerMemoryLimitMiB,
                        minimumMiB: AppConstants.SettingsLimits.minimumRedisContainerMemoryLimitMiB,
                        maximumMiB: AppConstants.SettingsLimits.maximumRedisContainerMemoryLimitMiB
                    )
                    .disabled(!viewModel.capabilities.canControlRuntimeServices || !viewModel.settings.containerMemoryLimitsEnabled)
                }
                settingsSection(AppConstants.Labels.recorderIngressHotColdPath) {
                    recorderIngressSettingsFields
                    settingHelp(AppConstants.Labels.recorderIngressHotColdPathHelp)
                }
                .disabled(!viewModel.capabilities.canControlRuntimeServices)
                settingsSection(AppConstants.Labels.sectionStorage) {
                    settingDirectoryField(
                        AppConstants.Labels.vitalFilesDirectory,
                        text: $viewModel.settings.vitalFilesDirectory
                    )
                }
                settingsSection(AppConstants.Labels.sectionHelperBackups) {
                    appliedSettingsStatus(backupAppliedSettingsSummary)
                    settingToggle(AppConstants.Labels.automaticBackups, isOn: $viewModel.settings.automaticBackupEnabled)
                    settingHelp(AppConstants.Labels.backupTimezoneHelp(TimeZone.current.identifier))
                    settingRow(AppConstants.Labels.backupTimes) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.settings.backupScheduleTimes.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    TextField(
                                        "",
                                        text: backupScheduleTimeBinding(at: index)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 84)
                                    Button("-") {
                                        removeBackupScheduleTime(at: index)
                                    }
                                    .disabled(viewModel.settings.backupScheduleTimes.count <= 1)
                                }
                            }
                            Button("+") {
                                viewModel.settings.backupScheduleTimes.append(nextBackupScheduleTime())
                            }
                        }
                    }
                    settingHelp(AppConstants.Labels.backupTimesHelp)
                    settingRow(AppConstants.Labels.backupRetention) {
                        HStack(spacing: 12) {
                            settingSliderControl(
                                value: $viewModel.settings.backupRetentionCount,
                                range: AppConstants.SettingsLimits.minimumBackupRetentionCount...AppConstants.SettingsLimits.maximumBackupRetentionCount,
                                step: AppConstants.SettingsLimits.backupRetentionStep,
                                suffix: "archives"
                            )
                            Button(AppConstants.Actions.openBackups) {
                                viewModel.openRuntimeDataBackups()
                            }
                            .disabled(!viewModel.capabilities.canOpenLocalFiles)
                        }
                    }
                    settingHelp(AppConstants.Labels.backupRetentionHelp)
                }
                settingsSection(AppConstants.Labels.sectionLogs) {
                    appliedSettingsStatus(logArchiveAppliedSettingsSummary)
                    settingSlider(
                        AppConstants.Labels.logArchiveRetention,
                        value: $viewModel.settings.logArchiveRetentionDays,
                        range: AppConstants.SettingsLimits.minimumLogArchiveRetentionDays...AppConstants.SettingsLimits.maximumLogArchiveRetentionDays,
                        step: AppConstants.SettingsLimits.logArchiveRetentionStepDays,
                        suffix: "days"
                    )
                    settingHelp(AppConstants.Labels.logArchiveRetentionHelp)
                    settingSlider(
                        AppConstants.Labels.logArchiveMaximum,
                        value: $viewModel.settings.logArchiveMaximumGiB,
                        range: AppConstants.SettingsLimits.minimumLogArchiveMaximumGiB...AppConstants.SettingsLimits.maximumLogArchiveMaximumGiB,
                        step: AppConstants.SettingsLimits.logArchiveMaximumStepGiB,
                        suffix: AppConstants.Labels.unitGiB
                    )
                    settingHelp(AppConstants.Labels.logArchiveMaximumHelp)
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
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
        .onAppear {
            guard viewModel.canDisplayPlatformSettings else {
                return
            }
            clampCPUCountToSystemLimit()
            clampMemoryToSystemLimit()
            clampReplayThroughput()
            clampContainerMemoryLimits()
            normalizeContainerMemoryLimitTotal()
            normalizeRecorderArchiveDefaults()
        }
        .onChange(of: viewModel.settings.cpuCount) {
            clampCPUCountToSystemLimit()
        }
        .onChange(of: viewModel.settings.memoryGiB) {
            clampMemoryToSystemLimit()
            clampContainerMemoryLimits()
            normalizeContainerMemoryLimitTotal()
        }
        .onChange(of: viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond) {
            clampReplayThroughput()
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.recorderIngressSendDataMode) {
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.recorderIngress) {
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.containerMemoryLimitsEnabled) {
            if viewModel.settings.containerMemoryLimitsEnabled {
                normalizeContainerMemoryLimitTotal()
            }
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.vitalServerContainerMemoryLimitMiB) {
            clampContainerMemoryLimits()
            normalizeContainerMemoryLimitTotal()
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.recorderIngressContainerMemoryLimitMiB) {
            clampContainerMemoryLimits()
            normalizeContainerMemoryLimitTotal()
            enableGuestStackReconcileActivationWhenNeeded()
        }
        .onChange(of: viewModel.settings.redisContainerMemoryLimitMiB) {
            clampContainerMemoryLimits()
            normalizeContainerMemoryLimitTotal()
            enableGuestStackReconcileActivationWhenNeeded()
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
        if !viewModel.platformSettingsReadIssues.isEmpty {
            settingsSection(AppConstants.Labels.settingsReadIssues) {
                ForEach(viewModel.platformSettingsReadIssues, id: \.source) { issue in
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

    private var recorderLoadControlBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.settings.recorderIngressSendDataMode == .spoolAndReplay
            },
            set: { enabled in
                viewModel.settings.recorderIngressSendDataMode = enabled ? .spoolAndReplay : .observeOnly
            }
        )
    }

    private var recorderLoadControlEnabled: Bool {
        viewModel.settings.recorderIngressSendDataMode == .spoolAndReplay
    }

    private func normalizeRecorderArchiveDefaults() {
        viewModel.settings.recorderIngress.rawArchiveEnabled = true
        viewModel.settings.recorderIngress.rawArchiveAutoExportEnabled = true
    }

    private func enableGuestStackReconcileActivationWhenNeeded() {
        let decision = restartNoticePolicy.decision(draft: viewModel.settings, runtime: viewModel.runtimeSettings)
        if decision.requiresGuestStackReconcile && !decision.requiresRestart {
            viewModel.settings.restartAfterSave = true
        }
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

    private var vmMemoryMiB: Int {
        max(viewModel.settings.memoryGiB * 1024, 1)
    }

    private var containerMemoryLimitTotalPercent: Int {
        containerMemoryLimitPercent(viewModel.settings.vitalServerContainerMemoryLimitMiB)
            + containerMemoryLimitPercent(viewModel.settings.recorderIngressContainerMemoryLimitMiB)
            + containerMemoryLimitPercent(viewModel.settings.redisContainerMemoryLimitMiB)
    }

    private var containerMemoryLimitTotalText: String {
        "\(containerMemoryLimitTotalPercent)% / \(AppConstants.SettingsLimits.maximumCombinedContainerMemoryLimitPercent)%"
    }

    private var vitalServerContainerMemoryLimitRange: ClosedRange<Int> {
        AppConstants.SettingsLimits.minimumVitalServerContainerMemoryLimitMiB...containerMemoryLimitUpperBound(
            configuredMaximumMiB: AppConstants.SettingsLimits.maximumVitalServerContainerMemoryLimitMiB,
            minimumMiB: AppConstants.SettingsLimits.minimumVitalServerContainerMemoryLimitMiB
        )
    }

    private var recorderIngressContainerMemoryLimitRange: ClosedRange<Int> {
        AppConstants.SettingsLimits.minimumRecorderIngressContainerMemoryLimitMiB...containerMemoryLimitUpperBound(
            configuredMaximumMiB: AppConstants.SettingsLimits.maximumRecorderIngressContainerMemoryLimitMiB,
            minimumMiB: AppConstants.SettingsLimits.minimumRecorderIngressContainerMemoryLimitMiB
        )
    }

    private var redisContainerMemoryLimitRange: ClosedRange<Int> {
        AppConstants.SettingsLimits.minimumRedisContainerMemoryLimitMiB...containerMemoryLimitUpperBound(
            configuredMaximumMiB: AppConstants.SettingsLimits.maximumRedisContainerMemoryLimitMiB,
            minimumMiB: AppConstants.SettingsLimits.minimumRedisContainerMemoryLimitMiB
        )
    }

    private func containerMemoryLimitUpperBound(configuredMaximumMiB: Int, minimumMiB: Int) -> Int {
        let vmMemoryMiB = viewModel.settings.memoryGiB * 1024
        return max(minimumMiB, min(configuredMaximumMiB, vmMemoryMiB))
    }

    private func containerMemoryLimitPercent(_ valueMiB: Int) -> Int {
        Int((Double(valueMiB) / Double(vmMemoryMiB) * 100.0).rounded())
    }

    private func containerMemoryLimitMiB(
        percent: Int,
        minimumMiB: Int,
        maximumMiB: Int
    ) -> Int {
        let rawMiB = Int((Double(vmMemoryMiB) * Double(percent) / 100.0).rounded())
        return min(max(rawMiB, minimumMiB), min(maximumMiB, vmMemoryMiB))
    }

    private func containerMemoryLimitPercentRange(
        minimumMiB: Int,
        maximumMiB: Int
    ) -> ClosedRange<Int> {
        let lower = max(1, Int(ceil(Double(minimumMiB) / Double(vmMemoryMiB) * 100.0)))
        let upper = max(lower, min(100, Int(floor(Double(min(maximumMiB, vmMemoryMiB)) / Double(vmMemoryMiB) * 100.0))))
        return lower...upper
    }

    private func otherContainerMemoryLimitPercentTotal(excluding target: ContainerMemoryLimitTarget) -> Int {
        switch target {
        case .vitalServer:
            return containerMemoryLimitPercent(viewModel.settings.recorderIngressContainerMemoryLimitMiB)
                + containerMemoryLimitPercent(viewModel.settings.redisContainerMemoryLimitMiB)
        case .recorderIngress:
            return containerMemoryLimitPercent(viewModel.settings.vitalServerContainerMemoryLimitMiB)
                + containerMemoryLimitPercent(viewModel.settings.redisContainerMemoryLimitMiB)
        case .redis:
            return containerMemoryLimitPercent(viewModel.settings.vitalServerContainerMemoryLimitMiB)
                + containerMemoryLimitPercent(viewModel.settings.recorderIngressContainerMemoryLimitMiB)
        }
    }

    private var canApplySettingsForCurrentConnection: Bool {
        viewModel.capabilities.canEditRuntimeProviderResources
            || viewModel.capabilities.canEditNetworkExposure
            || viewModel.capabilities.canOpenLocalFiles
            || viewModel.capabilities.canResetAdminPassword
            || viewModel.capabilities.canControlRuntimeServices
    }

    private var restartNotice: RuntimeSettingsRestartNoticeDecision {
        restartNoticePolicy.decision(draft: viewModel.settings, runtime: viewModel.runtimeSettings)
    }

    private var backupAppliedSettingsSummary: String {
        AppConstants.Labels.appliedBackupSettingsSummary(
            prefix: backupSettingsChanged
                ? AppConstants.Labels.pendingAppliedSettingsPrefix
                : AppConstants.Labels.appliedSettingsPrefix,
            automaticBackupText: viewModel.savedSettings.automaticBackupEnabled
                ? AppConstants.Labels.automaticBackupsOn
                : AppConstants.Labels.automaticBackupsOff,
            scheduleTimes: viewModel.savedSettings.backupScheduleTimes.joined(separator: ", "),
            timezone: TimeZone.current.identifier,
            retentionCount: viewModel.savedSettings.backupRetentionCount
        )
    }

    private var logArchiveAppliedSettingsSummary: String {
        AppConstants.Labels.appliedLogArchiveSettingsSummary(
            prefix: logArchiveSettingsChanged
                ? AppConstants.Labels.pendingAppliedSettingsPrefix
                : AppConstants.Labels.appliedSettingsPrefix,
            retentionDays: viewModel.savedSettings.logArchiveRetentionDays,
            maximumGiB: viewModel.savedSettings.logArchiveMaximumGiB
        )
    }

    private var backupSettingsChanged: Bool {
        viewModel.settings.automaticBackupEnabled != viewModel.savedSettings.automaticBackupEnabled
            || viewModel.settings.backupScheduleTimes != viewModel.savedSettings.backupScheduleTimes
            || viewModel.settings.backupRetentionCount != viewModel.savedSettings.backupRetentionCount
    }

    private var logArchiveSettingsChanged: Bool {
        viewModel.settings.logArchiveRetentionDays != viewModel.savedSettings.logArchiveRetentionDays
            || viewModel.settings.logArchiveMaximumGiB != viewModel.savedSettings.logArchiveMaximumGiB
    }

    private var restartRuntimeSection: some View {
        settingsSection(AppConstants.Labels.changeActivation) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(restartNotice.message)
                        .font(.caption)
                        .foregroundStyle(restartNotice.requiresActivation ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    let savedNotice = restartNoticePolicy.decision(
                        draft: viewModel.savedSettings,
                        runtime: viewModel.runtimeSettings
                    )
                    if savedNotice.requiresActivation && savedNotice.message != restartNotice.message {
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
        let requiresActivation = restartNotice.requiresActivation || savedNotice.requiresActivation
        return Button {
            if requiresRestart {
                showingRestartVMRuntimeConfirmation = true
            } else if viewModel.prepareApplySettings() {
                showingApplySettingsConfirmation = true
            }
        } label: {
            Label(
                requiresRestart
                    ? AppConstants.Labels.requiresVMRestart
                    : requiresActivation
                        ? AppConstants.Labels.requiresGuestStackReconcile
                        : AppConstants.StatusText.noVMRuntimeRestartRequired,
                systemImage: requiresActivation
                    ? "arrow.clockwise.circle.fill"
                    : "checkmark.circle.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(requiresActivation ? .orange : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((requiresActivation ? Color.orange : Color.secondary).opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke((requiresActivation ? Color.orange : Color.secondary).opacity(0.35), lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(
            !requiresActivation
                || !viewModel.capabilities.canControlRuntimeServices
                || viewModel.isBusy
        )
        .help(requiresRestart ? AppConstants.StatusText.restartVMRuntimeConfirmation : AppConstants.StatusText.applySettingsConfirmation)
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

    private func clampReplayThroughput() {
        let value = viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond
        let minimum = AppConstants.SettingsLimits.minimumRecorderIngressReplayMaxMiBPerSecond
        let maximum = AppConstants.SettingsLimits.maximumRecorderIngressReplayMaxMiBPerSecond
        let clampedValue: Int
        if value <= minimum {
            clampedValue = minimum
        } else {
            let step = AppConstants.SettingsLimits.recorderIngressReplayThroughputStep
            clampedValue = min(maximum, max(step, Int((Double(value) / Double(step)).rounded()) * step))
        }
        if viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond != clampedValue {
            viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond = clampedValue
        }
    }

    private func clampContainerMemoryLimits() {
        let vitalServerLimit = clamped(viewModel.settings.vitalServerContainerMemoryLimitMiB, to: vitalServerContainerMemoryLimitRange)
        if viewModel.settings.vitalServerContainerMemoryLimitMiB != vitalServerLimit {
            viewModel.settings.vitalServerContainerMemoryLimitMiB = vitalServerLimit
        }
        let recorderIngressLimit = clamped(
            viewModel.settings.recorderIngressContainerMemoryLimitMiB,
            to: recorderIngressContainerMemoryLimitRange
        )
        if viewModel.settings.recorderIngressContainerMemoryLimitMiB != recorderIngressLimit {
            viewModel.settings.recorderIngressContainerMemoryLimitMiB = recorderIngressLimit
        }
        let redisLimit = clamped(viewModel.settings.redisContainerMemoryLimitMiB, to: redisContainerMemoryLimitRange)
        if viewModel.settings.redisContainerMemoryLimitMiB != redisLimit {
            viewModel.settings.redisContainerMemoryLimitMiB = redisLimit
        }
    }

    private func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func normalizeContainerMemoryLimitTotal() {
        let maximumPercent = AppConstants.SettingsLimits.maximumCombinedContainerMemoryLimitPercent
        guard containerMemoryLimitTotalPercent > maximumPercent else {
            return
        }
        reduceContainerMemoryLimitSurplus(maximumPercent, target: .vitalServer)
        reduceContainerMemoryLimitSurplus(maximumPercent, target: .redis)
        reduceContainerMemoryLimitSurplus(maximumPercent, target: .recorderIngress)
    }

    private func reduceContainerMemoryLimitSurplus(_ maximumPercent: Int, target: ContainerMemoryLimitTarget) {
        let surplus = containerMemoryLimitTotalPercent - maximumPercent
        guard surplus > 0 else {
            return
        }
        let current = containerMemoryLimitValue(target)
        let minimumMiB = containerMemoryLimitMinimumMiB(target)
        let currentPercent = containerMemoryLimitPercent(current)
        let minimumPercent = containerMemoryLimitPercentRange(
            minimumMiB: minimumMiB,
            maximumMiB: containerMemoryLimitMaximumMiB(target)
        ).lowerBound
        let nextPercent = max(minimumPercent, currentPercent - surplus)
        setContainerMemoryLimitValue(
            target,
            containerMemoryLimitMiB(
                percent: nextPercent,
                minimumMiB: minimumMiB,
                maximumMiB: containerMemoryLimitMaximumMiB(target)
            )
        )
    }

    private func containerMemoryLimitValue(_ target: ContainerMemoryLimitTarget) -> Int {
        switch target {
        case .vitalServer:
            return viewModel.settings.vitalServerContainerMemoryLimitMiB
        case .recorderIngress:
            return viewModel.settings.recorderIngressContainerMemoryLimitMiB
        case .redis:
            return viewModel.settings.redisContainerMemoryLimitMiB
        }
    }

    private func setContainerMemoryLimitValue(_ target: ContainerMemoryLimitTarget, _ value: Int) {
        switch target {
        case .vitalServer:
            viewModel.settings.vitalServerContainerMemoryLimitMiB = value
        case .recorderIngress:
            viewModel.settings.recorderIngressContainerMemoryLimitMiB = value
        case .redis:
            viewModel.settings.redisContainerMemoryLimitMiB = value
        }
    }

    private func containerMemoryLimitMinimumMiB(_ target: ContainerMemoryLimitTarget) -> Int {
        switch target {
        case .vitalServer:
            return AppConstants.SettingsLimits.minimumVitalServerContainerMemoryLimitMiB
        case .recorderIngress:
            return AppConstants.SettingsLimits.minimumRecorderIngressContainerMemoryLimitMiB
        case .redis:
            return AppConstants.SettingsLimits.minimumRedisContainerMemoryLimitMiB
        }
    }

    private func containerMemoryLimitMaximumMiB(_ target: ContainerMemoryLimitTarget) -> Int {
        switch target {
        case .vitalServer:
            return AppConstants.SettingsLimits.maximumVitalServerContainerMemoryLimitMiB
        case .recorderIngress:
            return AppConstants.SettingsLimits.maximumRecorderIngressContainerMemoryLimitMiB
        case .redis:
            return AppConstants.SettingsLimits.maximumRedisContainerMemoryLimitMiB
        }
    }

    private func backupScheduleTimeBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.settings.backupScheduleTimes.indices.contains(index) else {
                    return ""
                }
                return viewModel.settings.backupScheduleTimes[index]
            },
            set: { value in
                guard viewModel.settings.backupScheduleTimes.indices.contains(index),
                      let draft = validBackupTimeDraft(value, at: index)
                else {
                    return
                }
                viewModel.settings.backupScheduleTimes[index] = draft
            }
        )
    }

    private func removeBackupScheduleTime(at index: Int) {
        guard viewModel.settings.backupScheduleTimes.count > 1,
              viewModel.settings.backupScheduleTimes.indices.contains(index)
        else {
            return
        }
        viewModel.settings.backupScheduleTimes.remove(at: index)
    }

    private func nextBackupScheduleTime() -> String {
        let existing = Set(viewModel.settings.backupScheduleTimes)
        let preferredTimes = RuntimeSettingsInitialValues.backupScheduleTimes + ["15:15", "21:15", "09:15"]
        if let next = preferredTimes.first(where: { !existing.contains($0) }) {
            return next
        }
        for hour in 0...23 {
            let candidate = String(format: "%02d:15", hour)
            if !existing.contains(candidate) {
                return candidate
            }
        }
        for hour in 0...23 {
            for minute in 0...59 {
                let candidate = String(format: "%02d:%02d", hour, minute)
                if !existing.contains(candidate) {
                    return candidate
                }
            }
        }
        return RuntimeSettingsInitialValues.backupScheduleTimes[0]
    }

    private func validBackupTimeDraft(_ value: String, at index: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 5,
              trimmed.allSatisfy({ character in
                  character.isNumber || character == ":"
              })
        else {
            return nil
        }
        if trimmed.isEmpty {
            return trimmed
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else {
            return nil
        }
        guard !parts[0].isEmpty, parts[0].count <= 2 else {
            return nil
        }
        if parts.count == 1 {
            if parts[0].count == 2,
               let hour = Int(parts[0]),
               !(0...23).contains(hour) {
                return nil
            }
            return trimmed
        }

        guard parts[1].count <= 2 else {
            return nil
        }
        if parts[0].count == 2,
           let hour = Int(parts[0]),
           !(0...23).contains(hour) {
            return nil
        }
        if parts[1].count == 2,
           let minute = Int(parts[1]),
           !(0...59).contains(minute) {
            return nil
        }
        if trimmed.count == 5,
           !RuntimeBackupSchedulePolicy.isValidTime(trimmed) {
            return nil
        }
        if trimmed.count == 5,
           RuntimeBackupSchedulePolicy.isValidTime(trimmed),
           viewModel.settings.backupScheduleTimes.enumerated().contains(where: { pair in
               pair.offset != index && pair.element == trimmed
           }) {
            return nil
        }
        return trimmed
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

    private func appliedSettingsStatus(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
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

    private var containerMemoryLimitsToggleRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(AppConstants.Labels.containerMemoryLimits)
                .foregroundStyle(viewModel.settings.containerMemoryLimitsEnabled ? Color.primary : Color.secondary)
                .frame(width: 160, alignment: .leading)
            Toggle("", isOn: $viewModel.settings.containerMemoryLimitsEnabled)
                .labelsHidden()
            Text(containerMemoryLimitTotalText)
                .fontWeight(.medium)
                .foregroundStyle(containerMemoryLimitTotalColor)
                .frame(width: 90, alignment: .leading)
            Spacer()
        }
    }

    private var containerMemoryLimitTotalColor: Color {
        if containerMemoryLimitTotalPercent > AppConstants.SettingsLimits.maximumCombinedContainerMemoryLimitPercent {
            return .red
        }
        return viewModel.settings.containerMemoryLimitsEnabled ? .primary : .secondary
    }

    private func containerMemoryLimitSlider(
        _ label: String,
        target: ContainerMemoryLimitTarget,
        value: Binding<Int>,
        minimumMiB: Int,
        maximumMiB: Int
    ) -> some View {
        let percentRange = containerMemoryLimitPercentRange(minimumMiB: minimumMiB, maximumMiB: maximumMiB)
        return settingRow(label) {
            HStack(spacing: 12) {
                if sliderRangeCanMove(percentRange) {
                    Slider(
                        value: Binding(
                            get: {
                                Double(clamped(
                                    containerMemoryLimitPercent(value.wrappedValue),
                                    to: percentRange
                                ))
                            },
                            set: { nextPercent in
                                let otherTotal = otherContainerMemoryLimitPercentTotal(excluding: target)
                                let combinedMaximum = AppConstants.SettingsLimits.maximumCombinedContainerMemoryLimitPercent
                                let allowedUpper = max(percentRange.lowerBound, min(percentRange.upperBound, combinedMaximum - otherTotal))
                                let percent = min(max(Int(nextPercent.rounded()), percentRange.lowerBound), allowedUpper)
                                value.wrappedValue = containerMemoryLimitMiB(
                                    percent: percent,
                                    minimumMiB: minimumMiB,
                                    maximumMiB: maximumMiB
                                )
                            }
                        ),
                        in: Double(percentRange.lowerBound)...Double(percentRange.upperBound),
                        step: Double(AppConstants.SettingsLimits.containerMemoryLimitPercentStep)
                    )
                    .frame(width: 260)
                } else {
                    disabledSliderPlaceholder
                }
                Text(containerMemoryLimitText(value.wrappedValue))
                    .fontWeight(.medium)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }

    private func containerMemoryLimitText(_ valueMiB: Int) -> String {
        "\(containerMemoryLimitPercent(valueMiB))% (\(valueMiB) \(AppConstants.Labels.unitMiB))"
    }

    private func settingSliderControl(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = ""
    ) -> some View {
        let sliderRange = normalizedSliderRange(range)
        let sliderStep = normalizedSliderStep(step)
        let displayValue = clamped(value.wrappedValue, to: sliderRange)
        return HStack(spacing: 12) {
            if sliderRangeCanMove(sliderRange) {
                Slider(
                    value: Binding(
                        get: { Double(clamped(value.wrappedValue, to: sliderRange)) },
                        set: { value.wrappedValue = clamped(Int($0), to: sliderRange) }
                    ),
                    in: Double(sliderRange.lowerBound)...Double(sliderRange.upperBound),
                    step: Double(sliderStep)
                )
                .frame(width: 260)
            } else {
                disabledSliderPlaceholder
            }
            Text(suffix.isEmpty ? "\(displayValue)" : "\(displayValue) \(suffix)")
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
        }
    }

    private func normalizedSliderRange(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
        if range.lowerBound <= range.upperBound {
            return range
        }
        return range.upperBound...range.upperBound
    }

    private func normalizedSliderStep(_ step: Int) -> Int {
        max(step, 1)
    }

    private func sliderRangeCanMove(_ range: ClosedRange<Int>) -> Bool {
        range.upperBound > range.lowerBound
    }

    private var disabledSliderPlaceholder: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
            .frame(width: 260, height: 4)
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

    @ViewBuilder
    private var recorderIngressSettingsFields: some View {
        settingIntegerField(AppConstants.Labels.recorderIngressPendingMiB, value: $viewModel.settings.recorderIngress.sendDataMaxPendingMiB)
        settingIntegerField(AppConstants.Labels.recorderIngressRawArchiveFileMiB, value: $viewModel.settings.recorderIngress.rawArchiveMaxFileMiB)
        settingIntegerField(AppConstants.Labels.recorderIngressRawArchiveFiles, value: $viewModel.settings.recorderIngress.rawArchiveMaxFiles)
    }

    private func settingIntegerField(_ label: String, value: Binding<Int>) -> some View {
        settingRow(label) {
            TextField("", value: value, formatter: positiveIntegerFormatter)
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

    private var positiveIntegerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.allowsFloats = false
        return formatter
    }
}
