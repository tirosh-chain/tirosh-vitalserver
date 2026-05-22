import Foundation
import RuntimeCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: RuntimeController
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false
    @State private var showingDeleteBackupConfirmation = false
    @State private var showingRepairProxyConfirmation = false
    @State private var showingRepairDatastoreConfirmation = false
    @State private var showingStartServicesConfirmation = false
    @State private var showingStopServicesConfirmation = false
    @State private var showingUninstallConfirmation = false
    @State private var showingCleanUninstallConfirmation = false
    @State private var showingApplySettingsConfirmation = false
    @State private var showingHealthDetails = false
    @State private var selectedTab = ManagerTab.status
    @State private var hoveredServiceLink: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tabSelector
            Group {
                switch selectedTab {
                case .status:
                    statusPanel
                case .settings:
                    settingsPanel
                case .update:
                    updatePanel
                case .advanced:
                    advancedPanel
                case .info:
                    infoPanel
                case .dangerZone:
                    dangerZonePanel
                case .log:
                    logPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 700)
        .alert(AppConstants.Actions.applySettings, isPresented: $showingApplySettingsConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.ok) {
                Task { await controller.applySettings() }
            }
        } message: {
            Text(controller.applySettingsConfirmation)
        }
        .alert(AppConstants.Actions.applyBundle, isPresented: $showingUpdateConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startUpdate) {
                Task { await controller.applySelectedBundle() }
            }
        } message: {
            Text(controller.selectedBundleConfirmation)
        }
        .alert(AppConstants.Actions.rollback, isPresented: $showingRollbackConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRollback, role: .destructive) {
                Task { await controller.rollbackRuntime() }
            }
        } message: {
            Text(controller.selectedBackupPath.isEmpty ? AppConstants.StatusText.latestBackupFallback : controller.selectedBackupPath)
        }
        .alert(AppConstants.Actions.deleteBackup, isPresented: $showingDeleteBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.deleteBackup, role: .destructive) {
                Task { await controller.deleteSelectedBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.deleteBackupConfirmation,
                controller.selectedBackupPath,
            ].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        .alert(AppConstants.Actions.repairProxyPort, isPresented: $showingRepairProxyConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairProxy, role: .destructive) {
                Task { await controller.repairProxyPort() }
            }
        } message: {
            Text(AppConstants.StatusText.repairProxyConfirmation)
        }
        .alert(AppConstants.Actions.repairDatastore, isPresented: $showingRepairDatastoreConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairDatastore, role: .destructive) {
                Task { await controller.repairDatastore() }
            }
        } message: {
            Text(AppConstants.StatusText.repairDatastoreConfirmation)
        }
        .alert(AppConstants.Actions.startRuntimeServices, isPresented: $showingStartServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRuntimeServices) {
                Task { await controller.startRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.startRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.stopRuntimeServices, isPresented: $showingStopServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.stopRuntimeServices, role: .destructive) {
                Task { await controller.stopRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.stopRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.standardUninstall, isPresented: $showingUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.uninstall, role: .destructive) {
                Task { await controller.uninstallRuntime() }
            }
        } message: {
            Text(AppConstants.StatusText.standardUninstallConfirmation)
        }
        .alert(AppConstants.Actions.cleanUninstall, isPresented: $showingCleanUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                Task { await controller.uninstallRuntime(clean: true) }
            }
        } message: {
            Text(AppConstants.StatusText.cleanUninstallConfirmation)
        }
        .task {
            await controller.refresh()
        }
        .task {
            await pollStatus()
        }
        .task {
            await pollLogs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Product.displayName)
                .font(.title)
                .fontWeight(.semibold)
            HStack(spacing: 4) {
                Text(AppConstants.Product.poweredByPrefix)
                    .foregroundStyle(.secondary)
                Button {
                    controller.openTiroshWebsite()
                } label: {
                    Text(AppConstants.Product.tiroshName)
                        .underline()
                        .foregroundStyle(
                            hoveredServiceLink == AppConstants.Product.tiroshName
                                ? Color.accentColor
                                : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredServiceLink = isHovering ? AppConstants.Product.tiroshName : nil
                }
                .help(AppConstants.Product.tiroshURL)
            }
            .font(.caption)
        }
    }

    private var tabSelector: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ManagerTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 640)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                statusRow(AppConstants.Labels.overallHealth) {
                    healthStatusValue
                }
                statusRow(AppConstants.Labels.vitalServer, vitalServerAvailability)
                statusRow(AppConstants.Labels.vitalServerURL) {
                    linkButton(AppConstants.Product.vitalServerURL(proxyPort: controller.status.proxyPort)) {
                        controller.openVitalServer()
                    }
                }
                statusRow(AppConstants.Labels.dataDirectory) {
                    linkButton(controller.settings.vitalFilesDirectory) {
                        controller.openVitalFilesDirectory()
                    }
                    .disabled(!controller.capabilities.canOpenLocalFiles)
                }
            }
            Divider()
            resourceUsageSection
            Divider()
            DisclosureGroup(AppConstants.Labels.healthDetails, isExpanded: $showingHealthDetails) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    ForEach(healthItems) { item in
                        healthRow(item)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var resourceUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.resourceUsage)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                resourceRow(
                    AppConstants.Labels.cpuUsage,
                    percent: controller.status.cpuUsagePercent,
                    detail: percentDetail(controller.status.cpuUsagePercent)
                )
                resourceRow(
                    AppConstants.Labels.memoryUsage,
                    usage: controller.status.memory
                )
                resourceRow(
                    AppConstants.Labels.systemDiskUsage,
                    usage: controller.status.systemDisk
                )
                resourceRow(
                    AppConstants.Labels.dataStorageUsage,
                    usage: controller.status.dataStorage
                )
            }
            Text(AppConstants.Labels.resourceUsageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overallHealthLabel: String {
        if controller.status.isReady {
            return AppConstants.StatusText.healthy
        }
        if !controller.status.runtimeInstalled {
            return AppConstants.StatusText.notInstalled
        }
        switch controller.status.runtimeState {
        case AppConstants.Values.stateCritical:
            return AppConstants.StatusText.critical
        case AppConstants.Values.stateDegraded, AppConstants.Values.stateRecovering:
            return AppConstants.StatusText.needsAttention
        default:
            return AppConstants.StatusText.starting
        }
    }

    private var overallHealthColor: Color {
        if controller.status.isReady {
            return .green
        }
        if !controller.status.runtimeInstalled {
            return .red
        }
        switch controller.status.runtimeState {
        case AppConstants.Values.stateCritical:
            return .red
        case AppConstants.Values.stateDegraded, AppConstants.Values.stateRecovering:
            return .orange
        default:
            return .orange
        }
    }

    private var healthStatusValue: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(overallHealthColor)
                .frame(width: 11, height: 11)
            Text(overallHealthLabel)
                .fontWeight(.medium)
        }
    }

    private var healthItems: [HealthItem] {
        [
            HealthItem(
                label: AppConstants.Labels.managerRuntime,
                value: controller.status.runtimeInstalled ? AppConstants.StatusText.ready : AppConstants.StatusText.notInstalled,
                isHealthy: controller.status.runtimeInstalled
            ),
            HealthItem(
                label: AppConstants.Labels.vmIPAddress,
                value: controller.status.vmIP ?? AppConstants.StatusText.waiting,
                isHealthy: controller.status.vmServiceLoaded && controller.status.vmIP != nil
            ),
            HealthItem(
                label: AppConstants.Labels.vitalServerApp,
                value: serviceReachabilityLabel(controller.status.guestHTTP),
                isHealthy: isSuccessfulHTTPStatus(controller.status.guestHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.hostProxyService,
                value: serviceReachabilityLabel(controller.status.hostProxyHTTP),
                isHealthy: controller.status.proxyServiceLoaded && isSuccessfulHTTPStatus(controller.status.hostProxyHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.redis,
                value: serviceReachabilityLabel(controller.status.redisUIHTTP),
                isHealthy: isSuccessfulHTTPStatus(controller.status.redisUIHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.watchdog,
                value: controller.status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded,
                isHealthy: controller.status.watchdogServiceLoaded
            ),
        ]
    }

    private var advancedStatusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
            GridRow {
                Text(AppConstants.Labels.runtimeState)
                    .foregroundStyle(.secondary)
                statusBadge
            }
            statusRow(
                AppConstants.Labels.runtime,
                controller.status.runtimeInstalled
                    ? AppConstants.StatusText.installed
                    : AppConstants.StatusText.notInstalled
            )
            statusRow(AppConstants.Labels.operation, controller.status.operation ?? AppConstants.StatusText.unknown)
            statusRow(AppConstants.Labels.runtimeVersion, controller.status.runtimeVersion ?? AppConstants.StatusText.unknown)
            statusRow(AppConstants.Labels.updatedAt, controller.status.updatedAt ?? AppConstants.StatusText.unknown)
            statusRow(
                AppConstants.Labels.vmService,
                controller.status.vmServiceLoaded
                    ? AppConstants.StatusText.loaded
                    : AppConstants.StatusText.notLoaded
            )
            statusRow(
                AppConstants.Labels.proxyService,
                controller.status.proxyServiceLoaded
                    ? AppConstants.StatusText.loaded
                    : AppConstants.StatusText.notLoaded
            )
            statusRow(
                AppConstants.Labels.watchdogService,
                controller.status.watchdogServiceLoaded
                    ? AppConstants.StatusText.loaded
                    : AppConstants.StatusText.notLoaded
            )
            statusRow(AppConstants.Labels.proxyPort, String(controller.status.proxyPort))
            statusRow(AppConstants.Labels.vmIP, controller.status.vmIP ?? AppConstants.StatusText.waiting)
            statusRow(AppConstants.Labels.guestHTTP, controller.status.guestHTTP ?? AppConstants.StatusText.notChecked)
            statusRow(AppConstants.Labels.hostProxy, controller.status.hostProxyHTTP ?? AppConstants.StatusText.notChecked)
            statusRow(AppConstants.Labels.redisUIHTTP, controller.status.redisUIHTTP ?? AppConstants.StatusText.notChecked)
            statusRow(AppConstants.Labels.swaggerUIHTTP, controller.status.swaggerUIHTTP ?? AppConstants.StatusText.notChecked)
            if !controller.status.failureReasons.isEmpty {
                statusRow(AppConstants.Labels.failureReasons, controller.status.failureReasonText)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var vitalServerAvailability: String {
        if isSuccessfulHTTPStatus(controller.status.hostProxyHTTP) {
            return AppConstants.StatusText.available
        }
        if controller.status.runtimeInstalled {
            return AppConstants.StatusText.waiting
        }
        return AppConstants.StatusText.unavailable
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        statusRow(label) {
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func statusRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        statusRow(label) {
            Text(path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.link)
    }

    private func healthRow(_ item: HealthItem) -> some View {
        GridRow {
            Text(item.label)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(item.isHealthy ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(item.value)
                    .fontWeight(.medium)
            }
        }
    }

    private func resourceRow(_ label: String, usage: ResourceUsage?) -> some View {
        resourceRow(
            label,
            percent: usage?.percent,
            detail: usage.map { "\(formatBytes($0.usedBytes)) / \(formatBytes($0.totalBytes))" } ?? AppConstants.StatusText.notChecked
        )
    }

    private func resourceRow(_ label: String, percent: Double?, detail: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView(value: min(max(percent ?? 0, 0), 100), total: 100)
                    .frame(width: 160)
                Text(detail)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
    }

    private func percentDetail(_ percent: Double?) -> String {
        guard let percent else {
            return AppConstants.StatusText.notChecked
        }
        return "\(Int(percent.rounded()))%"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private var settingsPanel: some View {
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
        controller.settings.networkMode == AppConstants.Values.networkShared
            ? AppConstants.Labels.sharedNetworkHelp
            : AppConstants.Labels.bridgedNetworkHelp
    }

    private var updatePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                updateSourceCard
                bundleVerificationCard
                applyUpdateCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
    }

    private var updateSourceCard: some View {
        updateCard(AppConstants.Labels.sectionUpdateSource) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(AppConstants.Labels.offlineBundle)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(AppConstants.Labels.onlineUpdate)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(AppConstants.Labels.updateSourceHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppConstants.Labels.onlineUpdateUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    statusRow(AppConstants.Labels.selectedBundle) {
                        Text(controller.selectedBundlePath.isEmpty ? AppConstants.Labels.noUpdateBundleSelected : controller.selectedBundlePath)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Button(AppConstants.Actions.chooseBundle) {
                    Task { await controller.chooseUpdateBundle() }
                }
                .disabled(controller.isBusy || !controller.capabilities.canApplyBundle)
            }
        }
    }

    private var bundleVerificationCard: some View {
        updateCard(AppConstants.Labels.sectionBundleVerification) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.bundleVerificationHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !controller.selectedBundleSummary.isEmpty {
                    scrollableMonospacedText(controller.selectedBundleSummary, maxHeight: 120)
                }
                if !controller.selectedBundleVerification.isEmpty {
                    scrollableMonospacedText(
                        controller.selectedBundleVerification,
                        maxHeight: 180,
                        foregroundColor: controller.selectedBundleVerified ? .green : .red
                    )
                }
                Button(AppConstants.Actions.verifyBundle) {
                    Task { await controller.verifySelectedBundle() }
                }
                .disabled(
                    controller.isBusy
                        || controller.selectedBundlePath.isEmpty
                        || !controller.capabilities.canApplyBundle
                )
            }
        }
    }

    private var applyUpdateCard: some View {
        updateCard(AppConstants.Labels.sectionApplyUpdate) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.applyUpdateHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                applyBundleActionRow
                if controller.isBusy {
                    Text(AppConstants.Labels.updateProgressLog)
                        .font(.caption)
                        .fontWeight(.medium)
                    scrollableMonospacedText(controller.logText, maxHeight: 220)
                }
            }
        }
    }

    private var applyBundleActionRow: some View {
        HStack(spacing: 12) {
            Button(AppConstants.Actions.applyBundle) {
                showingUpdateConfirmation = true
            }
            .disabled(
                controller.isBusy
                    || controller.selectedBundlePath.isEmpty
                    || !controller.selectedBundleVerified
                    || !controller.status.runtimeInstalled
                    || !controller.capabilities.canApplyBundle
            )

            if controller.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(controller.operationDetail.isEmpty ? controller.message : controller.operationDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 420, alignment: .leading)
            }

            Spacer()
        }
    }

    private func updateCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var updateRecoveryCard: some View {
        advancedCard(AppConstants.Labels.sectionUpdateRecovery) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.updateRecoveryHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !controller.backups.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        settingRow(AppConstants.Labels.rollbackBackup) {
                            Picker("", selection: $controller.selectedBackupURL) {
                                ForEach(controller.backups) { backup in
                                    Text("\(backup.name) (\(backup.sizeText))").tag(Optional(backup.url))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 520)
                        }
                        if let selectedBackup = controller.selectedBackup {
                            statusRow(AppConstants.Labels.selectedBackup) {
                                Text(selectedBackup.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            statusRow(AppConstants.Labels.backupSize, selectedBackup.sizeText)
                        }
                    }
                } else if let latestBackup = controller.status.latestBackup {
                    Text("\(AppConstants.Labels.latestBackup): \(latestBackup)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button(AppConstants.Actions.rollback) {
                        showingRollbackConfirmation = true
                    }
                    .disabled(
                        controller.isBusy
                            || controller.selectedBackupPath.isEmpty
                            || !controller.capabilities.canRollback
                    )

                    Button(AppConstants.Actions.deleteBackup, role: .destructive) {
                        showingDeleteBackupConfirmation = true
                    }
                    .disabled(
                        controller.isBusy
                            || controller.selectedBackupPath.isEmpty
                            || !controller.capabilities.canRollback
                    )
                }
            }
        }
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

    private var advancedPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.advancedSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.advancedDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                diagnosticsCard
                serviceHealthCard
                networkOverridesCard
                adminOperationsCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
    }

    private var infoPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.infoSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.infoDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                productInfoCard
                bundledServicesCard
                runtimePathsCard
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(16)
        }
    }

    private var dangerZonePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.dangerZoneSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.dangerZoneDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                recoveryOperationsCard
                updateRecoveryCard
                runtimeReplacementCard
                destructiveOperationsCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
    }

    private var productInfoCard: some View {
        advancedCard(AppConstants.Labels.sectionProductInfo) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.helperVersion, helperAppVersion)
                statusRow(AppConstants.Labels.vitalServerVersion, controller.releaseInfo.vitalServerVersion)
                statusRow(AppConstants.Labels.installedRuntimeVersion, controller.status.runtimeVersion ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.packageIdentifier, AppConstants.Product.packageIdentifier)
            }
        }
    }

    private var bundledServicesCard: some View {
        advancedCard(AppConstants.Labels.sectionBundledServices) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text(AppConstants.Labels.serviceName)
                        .fontWeight(.semibold)
                    Text(AppConstants.Labels.serviceImage)
                        .fontWeight(.semibold)
                    Text(AppConstants.Labels.serviceVersion)
                        .fontWeight(.semibold)
                }
                ForEach(bundledServices) { service in
                    GridRow {
                        Text(service.name)
                            .foregroundStyle(.secondary)
                        Text(service.image)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text(service.version)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    private var runtimePathsCard: some View {
        advancedCard(AppConstants.Labels.sectionRuntimePaths) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                pathRow(AppConstants.Labels.appBundle, Bundle.main.bundlePath)
                pathRow(AppConstants.Labels.runtimeHome, AppConstants.Paths.vmHome)
                pathRow(AppConstants.Labels.dataDirectory, controller.settings.vitalFilesDirectory)
                pathRow(AppConstants.Labels.backupDirectory, AppConstants.Paths.backups)
            }
        }
    }

    private var runtimeReplacementCard: some View {
        advancedCard(AppConstants.Labels.sectionRuntimeReplacement) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.vmRootfsUpdatePlanned)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(AppConstants.Actions.vmRootfsUpdate) {}
                        .disabled(true)
                    Text(AppConstants.StatusText.planned)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var destructiveOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionDestructiveOperations) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.destructiveOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu(AppConstants.Actions.uninstall) {
                    Button(AppConstants.Actions.standardUninstall, role: .destructive) {
                        showingUninstallConfirmation = true
                    }
                    Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                        showingCleanUninstallConfirmation = true
                    }
                }
                .foregroundStyle(.red)
                .disabled(
                    controller.isBusy
                        || !controller.status.runtimeInstalled
                        || !controller.capabilities.canUninstallRuntime
                )
                .fixedSize()
            }
        }
    }

    private var helperAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? controller.releaseInfo.helperVersion
    }

    private var bundledServices: [RuntimeBundledServiceInfo] {
        controller.releaseInfo.services
    }

    private var diagnosticsCard: some View {
        advancedCard(AppConstants.Labels.sectionDiagnostics) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.runtimeState) { statusBadge }
                statusRow(AppConstants.Labels.operation, controller.status.operation ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.runtimeVersion, controller.status.runtimeVersion ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.updatedAt, controller.status.updatedAt ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.vmIP, controller.status.vmIP ?? AppConstants.StatusText.waiting)
                if !controller.status.failureReasons.isEmpty {
                    statusRow(AppConstants.Labels.failureReasons) {
                        Text(controller.status.failureReasonText)
                            .fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var serviceHealthCard: some View {
        advancedCard(AppConstants.Labels.sectionServiceHealth) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                serviceStateRow(
                    AppConstants.Labels.managerRuntime,
                    isHealthy: controller.status.runtimeInstalled,
                    value: controller.status.runtimeInstalled ? AppConstants.StatusText.installed : AppConstants.StatusText.notInstalled
                )
                serviceStateRow(
                    AppConstants.Labels.vmService,
                    isHealthy: controller.status.vmServiceLoaded,
                    value: controller.status.vmServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                serviceStateRow(
                    AppConstants.Labels.proxyService,
                    isHealthy: controller.status.proxyServiceLoaded,
                    value: controller.status.proxyServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                serviceStateRow(
                    AppConstants.Labels.watchdogService,
                    isHealthy: controller.status.watchdogServiceLoaded,
                    value: controller.status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                httpStateRow(
                    AppConstants.Labels.vitalServerApp,
                    value: controller.status.guestHTTP,
                    action: controller.openVitalServer
                )
                httpStateRow(
                    AppConstants.Labels.hostProxyService,
                    value: controller.status.hostProxyHTTP,
                    action: controller.openVitalServer
                )
                httpStateRow(
                    AppConstants.Labels.redisUI,
                    value: controller.status.redisUIHTTP,
                    action: controller.openRedisUI
                )
                httpStateRow(
                    AppConstants.Labels.swaggerUI,
                    value: controller.status.swaggerUIHTTP,
                    action: controller.openSwagger
                )
            }
        }
    }

    private var networkOverridesCard: some View {
        advancedCard(AppConstants.Labels.sectionNetworkOverrides) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppConstants.Labels.advancedNetworkHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                networkSubsection(AppConstants.Labels.sectionMacExposure) {
                    settingPortField(AppConstants.Labels.proxyPort, value: $controller.settings.proxyPort)
                    settingHelp(AppConstants.Labels.proxyPortHelp)
                }

                networkSubsection(AppConstants.Labels.sectionAdvertisedURL) {
                    settingTextField(AppConstants.Labels.publicHost, text: $controller.settings.publicHost)
                    settingHelp(AppConstants.Labels.publicHostHelp)
                    settingPortField(AppConstants.Labels.publicPort, value: $controller.settings.publicPort)
                    settingHelp(AppConstants.Labels.publicPortHelp)
                    settingRow(AppConstants.Labels.advertisedURLPreview) {
                        Text(advertisedURLPreview)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    }
                }

                networkSubsection(AppConstants.Labels.sectionPlannedNetworkFeatures) {
                    plannedNetworkRow(AppConstants.Labels.mdnsName, value: AppConstants.StatusText.planned, help: AppConstants.Labels.mdnsHelp)
                    plannedNetworkRow(AppConstants.Labels.bridgedNetworking, value: AppConstants.StatusText.planned, help: AppConstants.Labels.bridgedAdvancedHelp)
                    plannedNetworkRow(AppConstants.Labels.httpsTermination, value: AppConstants.StatusText.planned, help: AppConstants.Labels.httpsTerminationHelp)
                    plannedNetworkRow(AppConstants.Labels.staticVMAddress, value: AppConstants.StatusText.notAvailable, help: AppConstants.Labels.staticVMAddressHelp)
                }

                applyActionRow
            }
        }
    }

    private var advertisedURLPreview: String {
        let host = controller.settings.publicHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost = host.isEmpty ? AppConstants.Labels.advertisedURLSameHost : host
        return "http://\(displayHost):\(controller.settings.publicPort)/"
    }

    private func networkSubsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(.top, 2)
    }

    private func plannedNetworkRow(_ label: String, value: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            settingRow(label) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            settingHelp(help)
        }
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

    private var adminOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionAdminOperations) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.adminOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingToggle(AppConstants.Labels.resetAdminPassword, isOn: $controller.settings.changeAdminPassword)
                    .disabled(!controller.capabilities.canResetAdminPassword)
                if controller.settings.changeAdminPassword {
                    settingRow(AppConstants.Labels.newAdminPassword) {
                        SecureField("", text: $controller.settings.adminPassword)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }
                }
                applyActionRow
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppConstants.Labels.runtimeServiceControlHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(AppConstants.Actions.startRuntimeServices) {
                            showingStartServicesConfirmation = true
                        }
                        .disabled(
                            controller.isBusy
                                || !controller.status.runtimeInstalled
                                || !controller.capabilities.canControlRuntimeServices
                        )

                        Button(AppConstants.Actions.stopRuntimeServices) {
                            showingStopServicesConfirmation = true
                        }
                        .disabled(
                            controller.isBusy
                                || !controller.status.runtimeInstalled
                                || !controller.capabilities.canControlRuntimeServices
                        )
                    }
                }
            }
        }
    }

    private var recoveryOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionRecoveryOperations) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.recoveryOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(AppConstants.Actions.repairDatastore) {
                        showingRepairDatastoreConfirmation = true
                    }
                    .disabled(controller.isBusy || !controller.status.runtimeInstalled)

                    Button(AppConstants.Actions.repairProxy) {
                        showingRepairProxyConfirmation = true
                    }
                    .disabled(controller.isBusy || !controller.status.runtimeInstalled)
                }
            }
        }
    }

    private func advancedCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scrollableMonospacedText(
        _ text: String,
        maxHeight: CGFloat,
        foregroundColor: Color = .primary
    ) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight)
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serviceStateRow(
        _ label: String,
        isHealthy: Bool,
        value: String,
        action: (() -> Void)? = nil
    ) -> some View {
        GridRow {
            serviceName(label, action: action)
            HStack(spacing: 8) {
                Circle()
                    .fill(isHealthy ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }

    private func httpStateRow(
        _ label: String,
        value: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        let healthy = isSuccessfulHTTPStatus(value)
        return GridRow {
            serviceName(label, action: action)
            HStack(spacing: 8) {
                Circle()
                    .fill(healthy ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(serviceReachabilityLabel(value))
                    .fontWeight(.medium)
                if let value {
                    Text("HTTP \(value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func serviceName(_ label: String, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                Text(label)
                    .underline()
                    .foregroundStyle(
                        hoveredServiceLink == label
                            ? Color.accentColor
                            : Color.secondary
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                hoveredServiceLink = isHovering ? label : nil
            }
            .help(AppConstants.Labels.openServiceHelp(label))
        } else {
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        Text(controller.status.runtimeState ?? AppConstants.StatusText.unknown)
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusColor: Color {
        switch controller.status.runtimeState {
        case AppConstants.Values.stateHealthy:
            return .green
        case AppConstants.Values.stateInstalling, AppConstants.Values.stateUpdating, AppConstants.Values.stateRecovering:
            return .orange
        case AppConstants.Values.stateDegraded:
            return .yellow
        case AppConstants.Values.stateCritical:
            return .red
        default:
            return .gray
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func serviceReachabilityLabel(_ value: String?) -> String {
        if isSuccessfulHTTPStatus(value) {
            return AppConstants.StatusText.reachable
        }
        if value == AppConstants.StatusText.failed {
            return AppConstants.StatusText.needsRepair
        }
        return AppConstants.StatusText.waiting
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

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func settingStepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = ""
    ) -> some View {
        settingRow(label) {
            Stepper(value: value, in: range, step: step) {
                Text(suffix.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(suffix)")
                    .frame(width: 100, alignment: .leading)
            }
            .fixedSize()
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

    private func settingTextField(_ label: String, text: Binding<String>) -> some View {
        settingRow(label) {
            TextField("", text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 440)
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

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppConstants.Labels.log)
                    .font(.headline)
                Spacer()
                Picker(AppConstants.Labels.logSource, selection: $controller.selectedLogSource) {
                    ForEach(controller.availableLogSources()) { source in
                        Text(source.title).tag(source.id)
                    }
                }
                .frame(width: 210)
                .onChange(of: controller.selectedLogSource) { _ in
                    controller.refreshLogs()
                }
                Picker(AppConstants.Labels.logLines, selection: $controller.logLineLimit) {
                    ForEach(controller.availableLogLineLimits(), id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .frame(width: 150)
                .onChange(of: controller.logLineLimit) { _ in
                    controller.refreshLogs()
                }
                Toggle(AppConstants.Labels.logStreaming, isOn: $controller.logStreaming)
                    .toggleStyle(.checkbox)
                    .onChange(of: controller.logStreaming) { isLive in
                        if isLive {
                            controller.refreshLogs()
                        }
                    }
                Text(controller.logStreaming ? AppConstants.Labels.logLive : AppConstants.Labels.logPaused)
                    .font(.caption)
                    .foregroundStyle(controller.logStreaming ? .green : .secondary)
                Button(AppConstants.Actions.openLogs) {
                    controller.openLogs()
                }
                Button(AppConstants.Actions.exportLogs) {
                    Task { await controller.exportLogs() }
                }
                .disabled(controller.isBusy || !controller.capabilities.canExportLogs)
            }
            ScrollView {
                Text(controller.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func pollStatus() async {
        while !Task.isCancelled {
            if !controller.isBusy {
                await controller.refreshHealthStatus()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func pollLogs() async {
        while !Task.isCancelled {
            controller.refreshLogsIfLive()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private struct HealthItem: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let isHealthy: Bool
}

private enum ManagerTab: CaseIterable, Identifiable {
    case status
    case settings
    case update
    case log
    case info
    case advanced
    case dangerZone

    var id: Self { self }

    var title: String {
        switch self {
        case .status:
            return AppConstants.Labels.tabStatus
        case .settings:
            return AppConstants.Labels.tabSettings
        case .update:
            return AppConstants.Labels.tabUpdate
        case .log:
            return AppConstants.Labels.tabLog
        case .info:
            return AppConstants.Labels.tabInfo
        case .advanced:
            return AppConstants.Labels.tabAdvanced
        case .dangerZone:
            return AppConstants.Labels.tabDangerZone
        }
    }
}
