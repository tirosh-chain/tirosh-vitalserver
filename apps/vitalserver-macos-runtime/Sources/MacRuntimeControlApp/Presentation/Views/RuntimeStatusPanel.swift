import RuntimeControl
import Contracts
import AppKit
import SwiftUI

struct RuntimeStatusPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingRuntimeDetails: Bool
    @Binding var showingRecorderDetails: Bool
    @Binding var showingResourceUsage: Bool
    @Binding var showingHealthDetails: Bool
    @State private var uptimeNow = Date()
    private let displayPolicy = RuntimeStatusDisplayPolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                runtimeSummarySection
                Divider()
                recorderSummarySection
                Divider()
                DisclosureGroup(AppConstants.Labels.runtimeDetails, isExpanded: $showingRuntimeDetails) {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        statusRow(AppConstants.Labels.dataDirectory) {
                            linkButton(viewModel.settings.vitalFilesDirectory) {
                                viewModel.openVitalFilesDirectory()
                            }
                            .disabled(!viewModel.capabilities.canOpenLocalFiles)
                        }
                    }
                    .padding(.top, 8)
                }
                DisclosureGroup(AppConstants.Labels.recorderDetails, isExpanded: $showingRecorderDetails) {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        statusRow(AppConstants.Labels.knownRecorders, recorderSummary.knownRecorders)
                        statusRow(AppConstants.Labels.knownBeds, recorderSummary.knownBeds)
                        if let latestRecorder = recorderSummary.latestRecorder {
                            statusRow(AppConstants.Labels.latestRecorder, latestRecorder)
                        }
                        if let observedAt = recorderSummary.observedAt {
                            statusRow(AppConstants.Labels.recorderObservation, observedAt)
                        }
                    }
                    .padding(.top, 8)
                }
                DisclosureGroup(AppConstants.Labels.resourceUsage, isExpanded: $showingResourceUsage) {
                    resourceUsageSection
                        .padding(.top, 8)
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 760, alignment: .leading)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            uptimeNow = date
        }
    }

    private var runtimeSummarySection: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
            statusRow(AppConstants.Labels.overallHealth) {
                healthStatusValue
            }
            statusRow(GeneratedRelease.vitalServerName, vitalServerAvailability)
            statusRow(AppConstants.Labels.vitalServerURL) {
                linkButton(AppConstants.Product.vitalServerURL(proxyPort: viewModel.status.proxyPort)) {
                    viewModel.openVitalServer()
                }
            }
        }
    }

    private var recorderSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.vitalRecorder)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.activeRecorderConnections, recorderSummary.activeConnections)
                statusRow(AppConstants.Labels.onlineRecorders, recorderSummary.onlineRecorders)
                statusRow(AppConstants.Labels.staleRecorders, recorderSummary.staleRecorders)
                statusRow(AppConstants.Labels.recorderAnomalies, recorderSummary.anomalies)
            }
        }
    }

    private var resourceUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private var overallHealthValue: RuntimeStatusDisplayPolicy.StatusValue {
        displayPolicy.overallHealth(status: viewModel.status, observation: viewModel.containerObservation, now: uptimeNow)
    }

    private var overallHealthColor: Color {
        statusColor(overallHealthValue.severity)
    }

    private var healthStatusValue: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(overallHealthColor)
                .frame(width: 11, height: 11)
            Text(overallHealthValue.text)
                .fontWeight(.medium)
            uptimeSuffix(overallHealthValue.uptimeText)
        }
    }

    private var healthItems: [RuntimeStatusDisplayPolicy.HealthItem] {
        displayPolicy.healthDetails(status: viewModel.status, observation: viewModel.containerObservation, now: uptimeNow)
    }

    private var recorderSummary: RuntimeStatusDisplayPolicy.RecorderSummary {
        displayPolicy.recorderSummary(status: viewModel.status, observation: viewModel.containerObservation)
    }

    private var vitalServerAvailability: RuntimeStatusDisplayPolicy.StatusValue {
        displayPolicy.vitalServerAvailability(status: viewModel.status, observation: viewModel.containerObservation, now: uptimeNow)
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        statusRow(label) {
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func statusRow(_ label: String, _ value: RuntimeStatusDisplayPolicy.StatusValue) -> some View {
        statusRow(label) {
            statusValue(value)
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
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
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

    private func statusValue(_ value: RuntimeStatusDisplayPolicy.StatusValue) -> some View {
        HStack(spacing: 8) {
            Text(value.text)
                .fontWeight(.medium)
            uptimeSuffix(value.uptimeText)
        }
    }

    @ViewBuilder
    private func uptimeSuffix(_ uptime: String?) -> some View {
        if let uptime {
            Text(uptime)
                .foregroundStyle(.secondary)
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
}
