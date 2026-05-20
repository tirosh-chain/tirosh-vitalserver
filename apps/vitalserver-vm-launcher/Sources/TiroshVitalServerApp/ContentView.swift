import SwiftUI

struct ContentView: View {
    @StateObject private var controller = RuntimeController()
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            TabView {
                statusGrid
                    .tabItem { Text("Status") }
                settingsPanel
                    .tabItem { Text("Settings") }
                updatePanel
                    .tabItem { Text("Update") }
            }
            .frame(minHeight: 360)
            actionBar
            logPanel
        }
        .padding(24)
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
            Button(AppConstants.Actions.uninstall) {
                Task { await controller.uninstallRuntime() }
            }
            .foregroundStyle(.red)
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
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
            Text(controller.selectedBundleSummary.isEmpty ? controller.selectedBundlePath : controller.selectedBundleSummary)
        }
        .alert(AppConstants.Actions.rollback, isPresented: $showingRollbackConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRollback, role: .destructive) {
                Task { await controller.rollbackRuntime() }
            }
        } message: {
            Text(controller.selectedBackupPath.isEmpty ? "Latest backup" : controller.selectedBackupPath)
        }
    }

    private var settingsPanel: some View {
        Form {
            Stepper(value: $controller.settings.cpuCount, in: 7...64) {
                labeledValue("CPU", "\(controller.settings.cpuCount)")
            }
            Stepper(value: $controller.settings.memoryGiB, in: 4...64, step: 4) {
                labeledValue("Memory", "\(controller.settings.memoryGiB) GiB")
            }
            Picker("Network", selection: $controller.settings.networkMode) {
                Text("Shared").tag("shared")
                Text("Bridged").tag("bridged")
            }
            if controller.settings.networkMode == "bridged" {
                TextField("Bridged interface", text: $controller.settings.bridgedInterface)
            }
            TextField("Vital files directory", text: $controller.settings.vitalFilesDirectory)
            Stepper(value: $controller.settings.proxyPort, in: 1...65_535) {
                labeledValue("Proxy port", "\(controller.settings.proxyPort)")
            }
            TextField("Public host", text: $controller.settings.publicHost)
            Stepper(value: $controller.settings.publicPort, in: 1...65_535) {
                labeledValue("Public port", "\(controller.settings.publicPort)")
            }
            SecureField("Admin password", text: $controller.settings.adminPassword)
            Toggle("Restart services after save", isOn: $controller.settings.restartAfterSave)
            Button(AppConstants.Actions.saveSettings) {
                Task { await controller.saveSettings() }
            }
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
        }
        .padding(16)
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBadge
            HStack {
                Text(controller.selectedBundlePath.isEmpty ? "No update bundle selected" : controller.selectedBundlePath)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(AppConstants.Actions.chooseBundle) {
                    controller.chooseUpdateBundle()
                }
            }
            if !controller.selectedBundleSummary.isEmpty {
                Text(controller.selectedBundleSummary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let latestBackup = controller.status.latestBackup {
                Text("Latest backup: \(latestBackup)")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if !controller.backups.isEmpty {
                Picker("Rollback backup", selection: $controller.selectedBackupPath) {
                    ForEach(controller.backups) { backup in
                        Text(backup.name).tag(backup.path)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(AppConstants.Actions.applyBundle) {
                    showingUpdateConfirmation = true
                }
                .disabled(controller.isBusy || controller.selectedBundlePath.isEmpty || !controller.status.runtimeInstalled)
                Button(AppConstants.Actions.rollback) {
                    showingRollbackConfirmation = true
                }
                .disabled(controller.isBusy || !controller.status.runtimeInstalled)
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
        case "healthy":
            return .green
        case "installing", "updating", "recovering":
            return .orange
        case "degraded":
            return .yellow
        case "critical":
            return .red
        default:
            return .gray
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
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

    private func pollStatus() async {
        while !Task.isCancelled {
            if !controller.isBusy {
                await controller.refreshHealthStatus()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }
}
