import RuntimeControl
import Contracts
import AppKit
import SwiftUI

struct RuntimeStatusPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingRecorderDetails: Bool
    @Binding var showingResourceUsage: Bool
    @State private var uptimeNow = Date()
    private let displayPolicy = RuntimeStatusDisplayPolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                runtimeSummarySection
                if let actionNeededItem {
                    Divider()
                    actionNeededSection(actionNeededItem)
                }
                Divider()
                recorderSummarySection
                Divider()
                RuntimeDisclosureSection(AppConstants.Labels.recorderDetails, isExpanded: $showingRecorderDetails) {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        statusRow(AppConstants.Labels.knownRecorders, recorderSummary.knownRecorders)
                        statusRow(AppConstants.Labels.knownBeds, recorderSummary.knownBeds)
                        if let latestRecorder = recorderSummary.latestRecorder {
                            statusRow(AppConstants.Labels.latestRecorder, latestRecorder)
                        }
                        if let observedAt = recorderSummary.observedAt {
                            statusRow(AppConstants.Labels.recorderObservation, viewModel.presentationFormatter.systemTimeText(observedAt))
                        }
                    }
                }
                RuntimeDisclosureSection(AppConstants.Labels.resourceUsage, isExpanded: $showingResourceUsage) {
                    resourceUsageSection
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
            statusRow(GeneratedRelease.vitalServerName) {
                vitalServerStatusAndURL
            }
            statusRow(AppConstants.Labels.dataDirectory) {
                dataDirectoryValue
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

    private var recorderSummary: RuntimeStatusDisplayPolicy.RecorderSummary {
        displayPolicy.recorderSummary(status: viewModel.status, observation: viewModel.containerObservation)
    }

    private var vitalServerAvailability: RuntimeStatusDisplayPolicy.StatusValue {
        displayPolicy.vitalServerAvailability(status: viewModel.status, observation: viewModel.containerObservation, now: uptimeNow)
    }

    private var vitalServerStatusAndURL: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                linkButton(AppConstants.Product.vitalServerURL(proxyPort: viewModel.status.proxyPort)) {
                    viewModel.openVitalServer()
                }
                statusValue(vitalServerAvailability)
            }
            VStack(alignment: .leading, spacing: 4) {
                linkButton(AppConstants.Product.vitalServerURL(proxyPort: viewModel.status.proxyPort)) {
                    viewModel.openVitalServer()
                }
                statusValue(vitalServerAvailability)
            }
        }
    }

    private var dataDirectoryValue: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dataDirectoryLink
                dataDirectoryStatsSuffix
            }
            VStack(alignment: .leading, spacing: 4) {
                dataDirectoryLink
                dataDirectoryStatsSuffix
            }
        }
    }

    private var dataDirectoryLink: some View {
        linkButton(viewModel.settings.vitalFilesDirectory) {
            viewModel.openVitalFilesDirectory()
        }
        .disabled(!viewModel.capabilities.canOpenLocalFiles)
    }

    @ViewBuilder
    private var dataDirectoryStatsSuffix: some View {
        if let stats = viewModel.status.dataDirectoryStats {
            Text("\(stats.fileCount) files · \(formatBytes(stats.sizeBytes))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text(AppConstants.StatusText.notChecked)
                .foregroundStyle(.secondary)
        }
    }

    private var actionNeededItem: RuntimeStatusDisplayPolicy.ActionNeededItem? {
        displayPolicy.actionNeeded(status: viewModel.status)
    }

    private func actionNeededSection(_ item: RuntimeStatusDisplayPolicy.ActionNeededItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.actionNeeded)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.overallHealth) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(item.severity))
                            .frame(width: 11, height: 11)
                        Text(item.title)
                            .fontWeight(.medium)
                    }
                }
                statusRow(AppConstants.Labels.recommendedAction, item.recommendedAction)
            }
        }
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
        if bytes < 1_024 {
            return "\(max(bytes, 0)) B"
        }
        let kib = Double(bytes) / 1_024
        if kib < 1_024 {
            return String(format: "%.1f KiB", kib)
        }
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", mib)
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
