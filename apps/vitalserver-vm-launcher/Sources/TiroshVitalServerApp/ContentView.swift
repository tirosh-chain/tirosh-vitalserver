import SwiftUI

struct ContentView: View {
    @StateObject private var controller = RuntimeController()
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false
    @State private var showingRepairProxyConfirmation = false
    @State private var showingUninstallConfirmation = false
    @State private var showingCleanUninstallConfirmation = false
    @State private var showingApplySettingsConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            TabView {
                statusGrid
                    .tabItem { Text(AppConstants.Labels.tabStatus) }
                settingsPanel
                    .tabItem { Text(AppConstants.Labels.tabSettings) }
                updatePanel
                    .tabItem { Text(AppConstants.Labels.tabUpdate) }
            }
            .frame(minHeight: 360)
            actionBar
            logPanel
        }
        .padding(24)
        .alert(AppConstants.Actions.applySettings, isPresented: $showingApplySettingsConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.applySettings) {
                Task { await controller.applySettings() }
            }
        } message: {
            Text(controller.applySettingsConfirmation)
        }
        .task {
            await controller.refresh()
        }
        .task {
            await pollStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Product.displayName)
                .font(.title)
                .fontWeight(.semibold)
            Text(AppConstants.Product.subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
            statusRow(
                AppConstants.Labels.runtime,
                controller.status.runtimeInstalled
                    ? AppConstants.StatusText.installed
                    : AppConstants.StatusText.notInstalled
            )
            statusRow(AppConstants.Labels.runtimeState, controller.status.runtimeState ?? AppConstants.StatusText.unknown)
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
            if !controller.status.failureReasons.isEmpty {
                statusRow(AppConstants.Labels.failureReasons, controller.status.failureReasons.joined(separator: ", "))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(AppConstants.Actions.healthCheck) {
                Task { await controller.healthCheck() }
            }
            Menu(AppConstants.Actions.open) {
                Button(AppConstants.Actions.openVitalServer) {
                    controller.openVitalServer()
                }
                Button(AppConstants.Actions.openRedisUI) {
                    controller.openRedisUI()
                }
                Button(AppConstants.Actions.openSwagger) {
                    controller.openSwagger()
                }
            }
            .fixedSize()
            Button(AppConstants.Actions.repairProxy) {
                showingRepairProxyConfirmation = true
            }
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
            Menu(AppConstants.Actions.uninstall) {
                Button(AppConstants.Actions.standardUninstall, role: .destructive) {
                    showingUninstallConfirmation = true
                }
                Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                    showingCleanUninstallConfirmation = true
                }
            }
            .foregroundStyle(.red)
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
            .fixedSize()
            Spacer()
            Button(AppConstants.Actions.refresh) {
                Task { await controller.refresh() }
            }
            .disabled(controller.isBusy)
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
        .alert(AppConstants.Actions.repairProxyPort, isPresented: $showingRepairProxyConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairProxy, role: .destructive) {
                Task { await controller.repairProxyPort() }
            }
        } message: {
            Text(AppConstants.StatusText.repairProxyConfirmation)
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
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(AppConstants.Labels.sectionVM) {
                    settingStepper(AppConstants.Labels.cpu, value: $controller.settings.cpuCount, range: 7...64, suffix: AppConstants.Labels.unitVCPU)
                    settingStepper(AppConstants.Labels.memory, value: $controller.settings.memoryGiB, range: 4...64, step: 4, suffix: AppConstants.Labels.unitGiB)
                }
                settingsSection(AppConstants.Labels.sectionNetwork) {
                    settingRow(AppConstants.Labels.mode) {
                        Picker("", selection: $controller.settings.networkMode) {
                            Text(AppConstants.Labels.shared).tag(AppConstants.Values.networkShared)
                            Text(AppConstants.Labels.bridged).tag(AppConstants.Values.networkBridged)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                    if controller.settings.networkMode == AppConstants.Values.networkBridged {
                        settingTextField(AppConstants.Labels.bridgedInterface, text: $controller.settings.bridgedInterface)
                    }
                    settingPortField(AppConstants.Labels.proxyPort, value: $controller.settings.proxyPort)
                    settingTextField(AppConstants.Labels.publicHost, text: $controller.settings.publicHost)
                    settingPortField(AppConstants.Labels.publicPort, value: $controller.settings.publicPort)
                }
                settingsSection(AppConstants.Labels.sectionStorage) {
                    settingDirectoryField(AppConstants.Labels.vitalFilesDirectory, text: $controller.settings.vitalFilesDirectory)
                }
                settingsSection(AppConstants.Labels.sectionOperations) {
                    settingToggle(AppConstants.Labels.startOnBoot, isOn: $controller.settings.startOnBoot)
                        .disabled(!controller.settings.startOnBootConfigurable)
                    settingToggle(AppConstants.Labels.restartServicesAfterSave, isOn: $controller.settings.restartAfterSave)
                    settingToggle(AppConstants.Labels.resetAdminPassword, isOn: $controller.settings.changeAdminPassword)
                    if controller.settings.changeAdminPassword {
                        settingRow(AppConstants.Labels.newAdminPassword) {
                            SecureField("", text: $controller.settings.adminPassword)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                        }
                    }
                }
                HStack {
                    Button(AppConstants.Actions.saveSettings) {
                        controller.saveSettingsDraft()
                    }
                    .disabled(controller.isBusy)
                    Button(AppConstants.Actions.applySettings) {
                        if controller.prepareApplySettings() {
                            showingApplySettingsConfirmation = true
                        }
                    }
                    .disabled(controller.isBusy || !controller.status.runtimeInstalled)
                    Spacer()
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBadge
            HStack {
                Text(controller.selectedBundlePath.isEmpty ? AppConstants.Labels.noUpdateBundleSelected : controller.selectedBundlePath)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(AppConstants.Actions.chooseBundle) {
                    Task { await controller.chooseUpdateBundle() }
                }
                .disabled(controller.isBusy)
                Button(AppConstants.Actions.verifyBundle) {
                    Task { await controller.verifySelectedBundle() }
                }
                .disabled(controller.isBusy || controller.selectedBundlePath.isEmpty)
            }
            if !controller.selectedBundleSummary.isEmpty {
                Text(controller.selectedBundleSummary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if !controller.selectedBundleVerification.isEmpty {
                Text(controller.selectedBundleVerification)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(controller.selectedBundleVerified ? .green : .red)
                    .textSelection(.enabled)
            }
            if let latestBackup = controller.status.latestBackup {
                Text("\(AppConstants.Labels.latestBackup): \(latestBackup)")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if !controller.backups.isEmpty {
                Picker(AppConstants.Labels.rollbackBackup, selection: $controller.selectedBackupPath) {
                    ForEach(controller.backups) { backup in
                        Text(backup.name).tag(backup.path)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(AppConstants.Actions.applyBundle) {
                    showingUpdateConfirmation = true
                }
                .disabled(
                    controller.isBusy
                        || controller.selectedBundlePath.isEmpty
                        || !controller.selectedBundleVerified
                        || !controller.status.runtimeInstalled
                )
                Button(AppConstants.Actions.rollback) {
                    showingRollbackConfirmation = true
                }
                .disabled(controller.isBusy || !controller.status.runtimeInstalled || controller.backups.isEmpty)
                Button(AppConstants.Actions.openLogs) {
                    controller.openLogs()
                }
                Spacer()
            }
        }
        .padding(16)
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
                Button(AppConstants.Actions.chooseDirectory) {
                    controller.chooseVitalFilesDirectory()
                }
                .disabled(controller.isBusy)
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
            Text(AppConstants.Labels.log)
                .font(.headline)
            ScrollView {
                Text(controller.message)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
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
}
