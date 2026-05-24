import RuntimeControl
import Contracts
import SwiftUI

struct RuntimeStatusPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingHealthDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                statusRow(AppConstants.Labels.overallHealth) {
                    healthStatusValue
                }
                statusRow(AppConstants.Labels.vitalServer, vitalServerAvailability)
                statusRow(AppConstants.Labels.vitalServerURL) {
                    linkButton(AppConstants.Product.vitalServerURL(proxyPort: viewModel.status.proxyPort)) {
                        viewModel.openVitalServer()
                    }
                }
                statusRow(AppConstants.Labels.dataDirectory) {
                    linkButton(viewModel.settings.vitalFilesDirectory) {
                        viewModel.openVitalFilesDirectory()
                    }
                    .disabled(!viewModel.capabilities.canOpenLocalFiles)
                }
            }
            Divider()
            recorderSection
            Divider()
            moduleUptimeSection
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

    private var moduleUptimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.moduleUptime)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                if let auditProxy = viewModel.containerObservation?.auditProxyStatus {
                    moduleRow(
                        AppConstants.Labels.auditProxy,
                        state: serviceReachabilityLabel(viewModel.containerObservation?.auditProxyHTTP),
                        uptimeSeconds: auditProxy.uptimeSeconds
                    )
                }
                ForEach(composeServices, id: \.service) { service in
                    moduleRow(
                        service.service,
                        state: service.health ?? service.state ?? AppConstants.StatusText.unknown,
                        uptimeSeconds: service.uptimeSeconds
                    )
                }
                if composeServices.isEmpty && viewModel.containerObservation?.auditProxyStatus == nil {
                    statusRow(AppConstants.Labels.moduleUptime, AppConstants.StatusText.notChecked)
                }
            }
        }
    }

    private var recorderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.vitalRecorder)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.activeRecorderConnections, activeRecorderConnectionText)
                statusRow(AppConstants.Labels.knownRecorders, knownRecorderText)
                if let latest = latestRecorder {
                    statusRow(AppConstants.Labels.latestRecorder, "\(latest.vrcode) \(latest.selectedIp ?? AppConstants.StatusText.unknown)")
                }
            }
        }
    }

    private var resourceUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.resourceUsage)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                resourceRow(
                    AppConstants.Labels.cpuUsage,
                    percent: viewModel.status.cpuUsagePercent,
                    detail: percentDetail(viewModel.status.cpuUsagePercent)
                )
                resourceRow(
                    AppConstants.Labels.memoryUsage,
                    usage: viewModel.status.memory
                )
                resourceRow(
                    AppConstants.Labels.systemDiskUsage,
                    usage: viewModel.status.systemDisk
                )
                resourceRow(
                    AppConstants.Labels.dataStorageUsage,
                    usage: viewModel.status.dataStorage
                )
            }
            Text(AppConstants.Labels.resourceUsageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overallHealthLabel: String {
        if viewModel.status.isReady {
            return AppConstants.StatusText.healthy
        }
        if !viewModel.status.runtimeInstalled {
            return AppConstants.StatusText.notInstalled
        }
        switch viewModel.status.runtimeState {
        case .some(.critical):
            return AppConstants.StatusText.critical
        case .some(.degraded), .some(.recovering):
            return AppConstants.StatusText.needsAttention
        default:
            return AppConstants.StatusText.starting
        }
    }

    private var overallHealthColor: Color {
        if viewModel.status.isReady {
            return .green
        }
        if !viewModel.status.runtimeInstalled {
            return .red
        }
        switch viewModel.status.runtimeState {
        case .some(.critical):
            return .red
        case .some(.degraded), .some(.recovering):
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
                value: viewModel.status.runtimeInstalled ? AppConstants.StatusText.ready : AppConstants.StatusText.notInstalled,
                isHealthy: viewModel.status.runtimeInstalled
            ),
            HealthItem(
                label: AppConstants.Labels.vmIPAddress,
                value: viewModel.status.vmIP ?? AppConstants.StatusText.waiting,
                isHealthy: viewModel.status.vmServiceLoaded && viewModel.status.vmIP != nil
            ),
            HealthItem(
                label: AppConstants.Labels.vitalServerApp,
                value: serviceReachabilityLabel(viewModel.status.guestHTTP),
                isHealthy: isSuccessfulHTTPStatus(viewModel.status.guestHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.hostProxyService,
                value: serviceReachabilityLabel(viewModel.status.hostProxyHTTP),
                isHealthy: viewModel.status.proxyServiceLoaded && isSuccessfulHTTPStatus(viewModel.status.hostProxyHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.redis,
                value: serviceReachabilityLabel(viewModel.status.redisUIHTTP),
                isHealthy: isSuccessfulHTTPStatus(viewModel.status.redisUIHTTP)
            ),
            HealthItem(
                label: AppConstants.Labels.watchdog,
                value: viewModel.status.watchdogServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.notLoaded,
                isHealthy: viewModel.status.watchdogServiceLoaded
            ),
        ]
    }

    private var activeRecorderConnectionText: String {
        let count = viewModel.containerObservation?.auditProxyStatus?.activeRecorderConnections ?? 0
        return "\(count)"
    }

    private var knownRecorderText: String {
        let count = viewModel.containerObservation?.auditProxyStatus?.recorders.count ?? 0
        return "\(count)"
    }

    private var latestRecorder: RuntimeRecorderConnectionObservation? {
        viewModel.containerObservation?.auditProxyStatus?.recorders
            .sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }
            .first
    }

    private var composeServices: [RuntimeContainerServiceObservation] {
        viewModel.containerObservation?.composeServices ?? []
    }

    private var vitalServerAvailability: String {
        if isSuccessfulHTTPStatus(viewModel.status.hostProxyHTTP) {
            return AppConstants.StatusText.available
        }
        if viewModel.status.runtimeInstalled {
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

    private func moduleRow(_ label: String, state: String, uptimeSeconds: Int?) -> some View {
        statusRow(label) {
            HStack(spacing: 8) {
                Text(state)
                    .fontWeight(.medium)
                Text(formatUptime(uptimeSeconds))
                    .foregroundStyle(.secondary)
            }
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

    private func formatUptime(_ seconds: Int?) -> String {
        guard let seconds else {
            return AppConstants.StatusText.unknown
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct HealthItem: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let isHealthy: Bool
}
