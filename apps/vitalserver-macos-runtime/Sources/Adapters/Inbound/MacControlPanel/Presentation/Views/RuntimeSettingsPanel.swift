import Foundation
import Contracts
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
                    settingRow(AppConstants.Labels.recorderIngressSendDataMode) {
                        recorderIngressSendDataModePicker
                    }
                    .disabled(!viewModel.capabilities.canControlRuntimeServices)
                    settingHelp(AppConstants.Labels.recorderIngressSendDataModeHelp)
                }
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

    private var recorderIngressSendDataModePicker: some View {
        Picker("", selection: $viewModel.settings.recorderIngressSendDataMode) {
            ForEach(RuntimeRecorderIngressSendDataMode.allCases, id: \.self) { mode in
                Text(recorderIngressSendDataModeLabel(mode))
                    .tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 420)
    }

    private func recorderIngressSendDataModeLabel(_ mode: RuntimeRecorderIngressSendDataMode) -> String {
        switch mode {
        case .passthrough:
            return AppConstants.Labels.recorderIngressSendDataModePassthrough
        case .mirrorSpool:
            return AppConstants.Labels.recorderIngressSendDataModeMirrorSpool
        case .spoolOnly:
            return AppConstants.Labels.recorderIngressSendDataModeSpoolOnly
        case .spoolAndReplay:
            return AppConstants.Labels.recorderIngressSendDataModeSpoolAndReplay
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
            showingRestartVMRuntimeConfirmation = true
        } label: {
            Label(
                requiresRestart
                    ? AppConstants.Labels.requiresVMRestart
                    : requiresActivation
                        ? AppConstants.Labels.requiresContainerReconcile
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
