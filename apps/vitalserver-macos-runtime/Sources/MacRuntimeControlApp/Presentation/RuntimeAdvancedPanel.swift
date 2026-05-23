import SwiftUI

struct RuntimeAdvancedPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingApplySettingsConfirmation: Bool
    @Binding var showingStartServicesConfirmation: Bool
    @Binding var showingStopServicesConfirmation: Bool
    @Binding var hoveredServiceLink: String?

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
                statusRow(AppConstants.Labels.operation, viewModel.status.operation?.rawValue ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.runtimeVersion, viewModel.status.runtimeVersion ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.updatedAt, viewModel.status.updatedAt ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.vmIP, viewModel.status.vmIP ?? AppConstants.StatusText.waiting)
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

    private var serviceHealthCard: some View {
        advancedCard(AppConstants.Labels.sectionServiceHealth) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                serviceStateRow(
                    AppConstants.Labels.managerRuntime,
                    isHealthy: viewModel.status.runtimeInstalled,
                    value: viewModel.status.runtimeInstalled ? AppConstants.StatusText.installed : AppConstants.StatusText.notInstalled
                )
                serviceStateRow(
                    AppConstants.Labels.vmService,
                    isHealthy: viewModel.status.vmServiceLoaded,
                    value: viewModel.status.vmServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                serviceStateRow(
                    AppConstants.Labels.proxyService,
                    isHealthy: viewModel.status.proxyServiceLoaded,
                    value: viewModel.status.proxyServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                serviceStateRow(
                    AppConstants.Labels.watchdogService,
                    isHealthy: viewModel.status.watchdogServiceLoaded,
                    value: viewModel.status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded
                )
                httpStateRow(
                    AppConstants.Labels.vitalServerApp,
                    value: viewModel.status.guestHTTP,
                    action: viewModel.openVitalServer
                )
                httpStateRow(
                    AppConstants.Labels.hostProxyService,
                    value: viewModel.status.hostProxyHTTP,
                    action: viewModel.openVitalServer
                )
                httpStateRow(
                    AppConstants.Labels.redisUI,
                    value: viewModel.status.redisUIHTTP,
                    action: viewModel.openRedisUI
                )
                httpStateRow(
                    AppConstants.Labels.swaggerUI,
                    value: viewModel.status.swaggerUIHTTP,
                    action: viewModel.openSwagger
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
                    settingPortField(AppConstants.Labels.proxyPort, value: $viewModel.settings.proxyPort)
                    settingHelp(AppConstants.Labels.proxyPortHelp)
                }

                networkSubsection(AppConstants.Labels.sectionAdvertisedURL) {
                    settingTextField(AppConstants.Labels.publicHost, text: $viewModel.settings.publicHost)
                    settingHelp(AppConstants.Labels.publicHostHelp)
                    settingPortField(AppConstants.Labels.publicPort, value: $viewModel.settings.publicPort)
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

    private var adminOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionAdminOperations) {
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
                            viewModel.isBusy
                                || !viewModel.status.runtimeInstalled
                                || !viewModel.capabilities.canControlRuntimeServices
                        )

                        Button(AppConstants.Actions.stopRuntimeServices) {
                            showingStopServicesConfirmation = true
                        }
                        .disabled(
                            viewModel.isBusy
                                || !viewModel.status.runtimeInstalled
                                || !viewModel.capabilities.canControlRuntimeServices
                        )
                    }
                }
            }
        }
    }

    private var advertisedURLPreview: String {
        let host = viewModel.settings.publicHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost = host.isEmpty ? AppConstants.Labels.advertisedURLSameHost : host
        return "http://\(displayHost):\(viewModel.settings.publicPort)/"
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
            .disabled(viewModel.isBusy || !viewModel.status.runtimeInstalled || !canApplySettingsForCurrentConnection)

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
    }

    private var statusBadge: some View {
        Text(viewModel.status.runtimeState?.rawValue ?? AppConstants.StatusText.unknown)
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
        case .some(.installing), .some(.updating), .some(.recovering):
            return .orange
        case .some(.degraded):
            return .yellow
        case .some(.critical):
            return .red
        default:
            return .gray
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
