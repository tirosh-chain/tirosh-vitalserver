import RuntimeControl
import RuntimeCore
import RuntimeContracts
import SwiftUI

struct RuntimeStatusPanel: View {
    @ObservedObject var controller: RuntimeController
    @Binding var showingHealthDetails: Bool

    var body: some View {
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
        case .some(.critical):
            return AppConstants.StatusText.critical
        case .some(.degraded), .some(.recovering):
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
}

private struct HealthItem: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let isHealthy: Bool
}
