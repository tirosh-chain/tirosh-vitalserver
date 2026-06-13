import SwiftUI
import Errors

struct RuntimeAdvancedPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingApplySettingsConfirmation: Bool
    @Binding var showingRollbackConfirmation: Bool
    @Binding var showingRestoreRuntimeDataBackupConfirmation: Bool
    @Binding var showingRepairProxyConfirmation: Bool
    @Binding var showingRepairDatastoreConfirmation: Bool
    @Binding var showingRepairVMDiskConfirmation: Bool
    @Binding var showingRepairRuntimeServicesConfirmation: Bool
    @Binding var showingRestartVMRuntimeConfirmation: Bool
    @Binding var showingStartServicesConfirmation: Bool
    @Binding var showingStopServicesConfirmation: Bool
    @Binding var hoveredServiceLink: String?
    @State private var uptimeNow = Date()
    @State private var showingVMHealth = true
    @State private var showingServiceHealth = true
    @State private var showingRecoveryOperations = false
    @State private var showingNetworkOverrides = false
    @State private var showingAdminOperations = false
    private let displayPolicy = RuntimeStatusDisplayPolicy()
    private let actionAvailabilityPolicy = RuntimeControlActionAvailabilityPolicy()

    init(
        viewModel: RuntimeViewModel,
        showingApplySettingsConfirmation: Binding<Bool>,
        showingRollbackConfirmation: Binding<Bool>,
        showingRestoreRuntimeDataBackupConfirmation: Binding<Bool>,
        showingRepairProxyConfirmation: Binding<Bool>,
        showingRepairDatastoreConfirmation: Binding<Bool>,
        showingRepairVMDiskConfirmation: Binding<Bool>,
        showingRepairRuntimeServicesConfirmation: Binding<Bool>,
        showingRestartVMRuntimeConfirmation: Binding<Bool>,
        showingStartServicesConfirmation: Binding<Bool>,
        showingStopServicesConfirmation: Binding<Bool>,
        hoveredServiceLink: Binding<String?>,
        showingVMHealth: Bool = true,
        showingServiceHealth: Bool = true,
        showingRecoveryOperations: Bool = false,
        showingNetworkOverrides: Bool = false,
        showingAdminOperations: Bool = false
    ) {
        self.viewModel = viewModel
        self._showingApplySettingsConfirmation = showingApplySettingsConfirmation
        self._showingRollbackConfirmation = showingRollbackConfirmation
        self._showingRestoreRuntimeDataBackupConfirmation = showingRestoreRuntimeDataBackupConfirmation
        self._showingRepairProxyConfirmation = showingRepairProxyConfirmation
        self._showingRepairDatastoreConfirmation = showingRepairDatastoreConfirmation
        self._showingRepairVMDiskConfirmation = showingRepairVMDiskConfirmation
        self._showingRepairRuntimeServicesConfirmation = showingRepairRuntimeServicesConfirmation
        self._showingRestartVMRuntimeConfirmation = showingRestartVMRuntimeConfirmation
        self._showingStartServicesConfirmation = showingStartServicesConfirmation
        self._showingStopServicesConfirmation = showingStopServicesConfirmation
        self._hoveredServiceLink = hoveredServiceLink
        self._showingVMHealth = State(initialValue: showingVMHealth)
        self._showingServiceHealth = State(initialValue: showingServiceHealth)
        self._showingRecoveryOperations = State(initialValue: showingRecoveryOperations)
        self._showingNetworkOverrides = State(initialValue: showingNetworkOverrides)
        self._showingAdminOperations = State(initialValue: showingAdminOperations)
    }

    var body: some View {
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
                vmHealthCard
                serviceHealthCard
                recoveryOperationsCard
                networkOverridesCard
                adminOperationsCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            uptimeNow = date
        }
        .onChange(of: viewModel.settings.proxyPort) {
            viewModel.syncAdvertisedURLWithProxyIfNeeded()
        }
        .onChange(of: viewModel.settings.runtimeControlPort) {
            viewModel.syncAdvertisedURLWithProxyIfNeeded()
        }
    }

    private var diagnosticsCard: some View {
        advancedCard(AppConstants.Labels.sectionDiagnostics) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.runtimeState) { statusBadge }
                statusRow(AppConstants.Labels.operation, viewModel.presentationFormatter.activeOperationText(viewModel.status))
                statusRow(AppConstants.Labels.runtimeVersion, viewModel.status.runtimeVersion ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.updatedAt, viewModel.presentationFormatter.systemTimeText(viewModel.status.updatedAt))
                if !viewModel.status.failureReasons.isEmpty {
                    statusRow(AppConstants.Labels.failureReasons) {
                        Text(viewModel.presentationFormatter.failureReasonText(viewModel.status))
                            .fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var vmHealthCard: some View {
        advancedDisclosureCard(AppConstants.Labels.sectionVMHealth, isExpanded: $showingVMHealth) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(vmHealthItems) { item in
                    healthRow(item)
                }
            }
        }
    }

    private var vmHealthItems: [RuntimeStatusDisplayPolicy.HealthItem] {
        displayPolicy.advancedVMHealth(status: viewModel.status)
    }

    private var serviceHealthCard: some View {
        advancedDisclosureCard(AppConstants.Labels.sectionServiceHealth, isExpanded: $showingServiceHealth) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                ForEach(serviceHealthItems) { item in
                    serviceHealthRow(item)
                }
            }
        }
    }

    private var serviceHealthItems: [RuntimeStatusDisplayPolicy.ServiceHealthItem] {
        displayPolicy.advancedServiceHealth(status: viewModel.status, observation: viewModel.containerObservation, now: uptimeNow)
    }

    private var recoveryOperationsCard: some View {
        advancedDisclosureCard(AppConstants.Labels.sectionRecoveryOperations, isExpanded: $showingRecoveryOperations) {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppConstants.Labels.recoveryOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                recoverySubsection(AppConstants.Labels.sectionUpdateRecovery) {
                    Text(AppConstants.Labels.updateRecoveryHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let backupListErrorMessage = viewModel.backupListErrorMessage {
                        Text(backupListErrorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !viewModel.backups.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            settingRow(AppConstants.Labels.rollbackBackup) {
                                Picker("", selection: $viewModel.selectedBackupPath) {
                                    ForEach(viewModel.backups) { backup in
                                        Text("\(backup.name) (\(viewModel.presentationFormatter.backupSizeText(backup)))")
                                            .tag(Optional(backup.path))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 520)
                            }
                            if let selectedBackup = viewModel.selectedBackup {
                                statusRow(AppConstants.Labels.selectedBackup) {
                                    Text(selectedBackup.path)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                statusRow(
                                    AppConstants.Labels.backupSize,
                                    viewModel.presentationFormatter.backupSizeText(selectedBackup)
                                )
                            }
                        }
                    } else if let latestBackup = viewModel.status.latestBackup {
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
                            viewModel.isBusy
                                || !viewModel.hasSelectedBackup
                                || !viewModel.capabilities.canRollback
                        )

                        Button(AppConstants.Actions.openBackups) {
                            viewModel.openRuntimeDataBackups()
                        }
                        .disabled(!viewModel.capabilities.canOpenLocalFiles)
                    }
                }

                Divider()

                recoverySubsection(AppConstants.Labels.sectionRuntimeDataRecovery) {
                    Text(AppConstants.Labels.runtimeDataRecoveryHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let backupListErrorMessage = viewModel.runtimeDataBackupListErrorMessage {
                        Text(backupListErrorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !viewModel.runtimeDataBackups.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            settingRow(AppConstants.Labels.runtimeDataBackup) {
                                Picker("", selection: $viewModel.selectedRuntimeDataBackupPath) {
                                    ForEach(viewModel.runtimeDataBackups) { backup in
                                        Text("\(backup.name) (\(viewModel.presentationFormatter.backupSizeText(backup)))")
                                            .tag(Optional(backup.path))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 520)
                            }
                            if let selectedBackup = viewModel.selectedRuntimeDataBackup {
                                statusRow(AppConstants.Labels.selectedBackup) {
                                    Text(selectedBackup.path)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                statusRow(
                                    AppConstants.Labels.backupSize,
                                    viewModel.presentationFormatter.backupSizeText(selectedBackup)
                                )
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button(AppConstants.Actions.createBackup) {
                            Task { await viewModel.createRuntimeDataBackup() }
                        }
                        .disabled(
                            !actionAvailabilityPolicy.canManageRuntimeDataBackup(
                                status: viewModel.status,
                                capabilities: viewModel.capabilities,
                                isBusy: viewModel.isBusy
                            )
                        )

                        Button(AppConstants.Actions.restoreBackup) {
                            showingRestoreRuntimeDataBackupConfirmation = true
                        }
                        .disabled(
                            !actionAvailabilityPolicy.canManageRuntimeDataBackup(
                                status: viewModel.status,
                                capabilities: viewModel.capabilities,
                                isBusy: viewModel.isBusy
                            )
                                || !viewModel.hasSelectedRuntimeDataBackup
                        )

                        Button(AppConstants.Actions.openBackups) {
                            viewModel.openBackups()
                        }
                        .disabled(!viewModel.capabilities.canOpenLocalFiles)
                    }
                    if viewModel.isCreatingRuntimeDataBackup {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.operationDetail.isEmpty ? viewModel.message : viewModel.operationDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                recoverySubsection(AppConstants.Labels.sectionRuntimeRepair) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button(AppConstants.Actions.restartVMRuntime) {
                                showingRestartVMRuntimeConfirmation = true
                            }
                            .disabled(!actionAvailabilityPolicy.canControlRuntimeServices(
                                status: viewModel.status,
                                capabilities: viewModel.capabilities,
                                isBusy: viewModel.isBusy
                            ))

                            Button(AppConstants.Actions.repairRuntimeServices) {
                                showingRepairRuntimeServicesConfirmation = true
                            }
                            .disabled(!actionAvailabilityPolicy.canRepairRuntime(
                                status: viewModel.status,
                                isBusy: viewModel.isBusy
                            ))

                            Button(AppConstants.Actions.repairDatastore) {
                                showingRepairDatastoreConfirmation = true
                            }
                            .disabled(!actionAvailabilityPolicy.canRepairRuntime(
                                status: viewModel.status,
                                isBusy: viewModel.isBusy
                            ))

                            Button(AppConstants.Actions.repairVMDisk) {
                                showingRepairVMDiskConfirmation = true
                            }
                            .disabled(!actionAvailabilityPolicy.canRepairRuntime(
                                status: viewModel.status,
                                isBusy: viewModel.isBusy
                            ))

                            Button(AppConstants.Actions.repairProxy) {
                                showingRepairProxyConfirmation = true
                            }
                            .disabled(!actionAvailabilityPolicy.canRepairRuntime(
                                status: viewModel.status,
                                isBusy: viewModel.isBusy
                            ))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppConstants.Labels.sectionRedisDataRecovery)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(AppConstants.Labels.redisDataRecoveryHelp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                Button(AppConstants.Actions.createRedisBackup) {
                                    Task { await viewModel.createRedisBackup() }
                                }
                                .disabled(
                                    !actionAvailabilityPolicy.canCreateRedisBackup(
                                        status: viewModel.status,
                                        capabilities: viewModel.capabilities,
                                        isBusy: viewModel.isBusy
                                    )
                                )
                                Button(AppConstants.Actions.restoreRedisBackup) {}
                                    .disabled(true)
                                Button(AppConstants.Actions.openBackups) {
                                    viewModel.openRedisBackups()
                                }
                                .disabled(!viewModel.capabilities.canOpenLocalFiles)
                                Text(AppConstants.StatusText.planned)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if viewModel.isCreatingRedisBackup {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(viewModel.operationDetail.isEmpty ? viewModel.message : viewModel.operationDetail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var networkOverridesCard: some View {
        advancedDisclosureCard(AppConstants.Labels.sectionNetworkOverrides, isExpanded: $showingNetworkOverrides) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppConstants.Labels.advancedNetworkHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                networkSubsection(AppConstants.Labels.sectionAdvertisedURLOverride) {
                    advertisedServiceURLFields
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

    private var adminOperationsCard: some View {
        advancedDisclosureCard(AppConstants.Labels.sectionAdminOperations, isExpanded: $showingAdminOperations) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.adminOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingToggle(AppConstants.Labels.resetAdminPassword, isOn: $viewModel.settings.changeAdminPassword)
                    .disabled(!viewModel.capabilities.canResetAdminPassword)
                if viewModel.settings.changeAdminPassword {
                    settingRow(AppConstants.Labels.newAdminPassword) {
                        SecureField("", text: $viewModel.settings.adminPassword)
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
                            !actionAvailabilityPolicy.canControlRuntimeServices(
                                status: viewModel.status,
                                capabilities: viewModel.capabilities,
                                isBusy: viewModel.isBusy
                            )
                        )

                        Button(AppConstants.Actions.stopRuntimeServices) {
                            showingStopServicesConfirmation = true
                        }
                        .disabled(
                            !actionAvailabilityPolicy.canControlRuntimeServices(
                                status: viewModel.status,
                                capabilities: viewModel.capabilities,
                                isBusy: viewModel.isBusy
                            )
                        )
                    }
                }
            }
        }
    }

    private var advertisedServiceURLFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingTextField(AppConstants.Labels.vitalServerAdvertisedURL, text: $viewModel.settings.vitalServerURL)
            settingHelp(AppConstants.Labels.vitalServerURLHelp)

            settingTextField(AppConstants.Labels.remoteConsoleAdvertisedURL, text: $viewModel.settings.remoteConsoleURL)
            settingHelp(AppConstants.Labels.remoteConsoleAdvertisedURLHelp)
        }
    }

    private var canApplySettingsForCurrentConnection: Bool {
        viewModel.capabilities.canEditVMResources
            || viewModel.capabilities.canEditNetworkExposure
            || viewModel.capabilities.canOpenLocalFiles
            || viewModel.capabilities.canResetAdminPassword
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

    private var statusBadge: some View {
        Text(viewModel.presentationFormatter.runtimeStateText(viewModel.status.runtimeState))
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusColor: Color {
        switch viewModel.status.runtimeState {
        case .some(.healthy):
            return .green
        case .some(.installing), .some(.initializing), .some(.updating), .some(.recovering):
            return .orange
        case .some(.degraded):
            return .yellow
        case .some(.critical):
            return .red
        default:
            return .gray
        }
    }

    private func advancedDisclosureCard<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RuntimeDisclosureSection(title, isExpanded: isExpanded) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func recoverySubsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
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

    private func healthRow(_ item: RuntimeStatusDisplayPolicy.HealthItem) -> some View {
        GridRow {
            Text(item.label)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(item.value.severity))
                    .frame(width: 9, height: 9)
                Text(item.value.text)
                    .fontWeight(.medium)
                uptimeSuffix(item.value.uptimeText)
            }
        }
    }

    private func serviceHealthRow(_ item: RuntimeStatusDisplayPolicy.ServiceHealthItem) -> some View {
        GridRow {
            serviceName(item.label, action: serviceAction(item.action))
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(item.value.severity))
                    .frame(width: 9, height: 9)
                Text(item.value.text)
                    .fontWeight(.medium)
                uptimeSuffix(item.value.uptimeText)
                if let value = item.httpStatus {
                    Text("HTTP \(value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func serviceAction(_ action: RuntimeStatusDisplayPolicy.ServiceAction?) -> (() -> Void)? {
        guard let action else {
            return nil
        }
        switch action {
        case .openVitalServer:
            return viewModel.openVitalServer
        case .openRedisUI:
            return viewModel.openRedisUI
        case .openSwagger:
            return viewModel.openSwagger
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

    @ViewBuilder
    private func uptimeSuffix(_ uptime: String?) -> some View {
        if let uptime {
            Text(uptime)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ severity: RuntimeStatusDisplayPolicy.Severity) -> Color {
        switch severity {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .gray
        }
    }

    private func settingHelp(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
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
