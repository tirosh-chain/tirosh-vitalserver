import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: RuntimeController
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false
    @State private var showingRepairProxyConfirmation = false
    @State private var showingUninstallConfirmation = false
    @State private var showingCleanUninstallConfirmation = false
    @State private var showingApplySettingsConfirmation = false
    @State private var showingHealthDetails = false
    @State private var selectedTab = ManagerTab.status

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
            Text(AppConstants.Product.poweredBy)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppConstants.Product.subtitle)
                .foregroundStyle(.secondary)
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
        .frame(width: 420)
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
                }
            }
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
                label: AppConstants.Labels.redisUI,
                value: serviceReachabilityLabel(controller.status.redisUIHTTP),
                isHealthy: isSuccessfulHTTPStatus(controller.status.redisUIHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.swaggerUI,
                value: serviceReachabilityLabel(controller.status.swaggerUIHTTP),
                isHealthy: isSuccessfulHTTPStatus(controller.status.swaggerUIHTTP)
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
                statusRow(AppConstants.Labels.failureReasons, controller.status.failureReasons.joined(separator: ", "))
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
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(AppConstants.Labels.sectionVM) {
                    settingSlider(AppConstants.Labels.cpu, value: $controller.settings.cpuCount, range: 7...64, suffix: AppConstants.Labels.unitVCPU)
                    settingSlider(AppConstants.Labels.memory, value: $controller.settings.memoryGiB, range: 4...64, step: 4, suffix: AppConstants.Labels.unitGiB)
                    settingSlider(
                        AppConstants.Labels.disk,
                        value: $controller.settings.diskGiB,
                        range: diskSizeRange,
                        step: 4,
                        suffix: AppConstants.Labels.unitGiB
                    )
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
        VStack(alignment: .leading, spacing: 14) {
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

    private var diskSizeRange: ClosedRange<Int> {
        let minimum = controller.settings.minimumDiskGiB
        return minimum...max(minimum, 512)
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
                        Text(controller.status.failureReasons.joined(separator: ", "))
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
                httpStateRow(AppConstants.Labels.vitalServerApp, value: controller.status.guestHTTP)
                httpStateRow(AppConstants.Labels.hostProxyService, value: controller.status.hostProxyHTTP)
                httpStateRow(AppConstants.Labels.redisUI, value: controller.status.redisUIHTTP)
                httpStateRow(AppConstants.Labels.swaggerUI, value: controller.status.swaggerUIHTTP)
            }
        }
    }

    private var networkOverridesCard: some View {
        advancedCard(AppConstants.Labels.sectionNetworkOverrides) {
            settingPortField(AppConstants.Labels.proxyPort, value: $controller.settings.proxyPort)
            settingHelp(AppConstants.Labels.proxyPortHelp)
            settingTextField(AppConstants.Labels.publicHost, text: $controller.settings.publicHost)
            settingPortField(AppConstants.Labels.publicPort, value: $controller.settings.publicPort)
            Button(AppConstants.Actions.applySettings) {
                if controller.prepareApplySettings() {
                    showingApplySettingsConfirmation = true
                }
            }
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
        }
    }

    private var adminOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionAdminOperations) {
            actionBar
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

    private func serviceStateRow(_ label: String, isHealthy: Bool, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(isHealthy ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }

    private func httpStateRow(_ label: String, value: String?) -> some View {
        let healthy = isSuccessfulHTTPStatus(value)
        return GridRow {
            Text(label)
                .foregroundStyle(.secondary)
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
        return code >= 200 && code < 400
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
                Button(AppConstants.Actions.refresh) {
                    controller.refreshLogs()
                }
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
            if controller.logStreaming {
                controller.refreshLogs()
            }
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
    case advanced
    case log

    var id: Self { self }

    var title: String {
        switch self {
        case .status:
            return AppConstants.Labels.tabStatus
        case .settings:
            return AppConstants.Labels.tabSettings
        case .update:
            return AppConstants.Labels.tabUpdate
        case .advanced:
            return AppConstants.Labels.tabAdvanced
        case .log:
            return AppConstants.Labels.tabLog
        }
    }
}
