import Contracts
import SwiftUI

struct RuntimeObservabilityPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var showingRuntimeEvents = true

    private let eventDisplayPolicy = RuntimeEventDisplayPolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pipelineSection
                anomalySection
                runtimeEventsSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack {
            Text(AppConstants.Labels.sectionObservability)
                .font(.headline)
            Spacer()
            Button(AppConstants.Actions.refresh) {
                viewModel.refreshRuntimeEvents()
                viewModel.refreshVitalRecorders()
            }
        }
    }

    private var pipelineSection: some View {
        observationSection("Observation pipeline") {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                metricRow(AppConstants.Labels.vitalDBObserver, observerStatus)
                metricRow(AppConstants.Labels.guestLogSyncService, viewModel.status.guestLogSyncServiceLoaded ? AppConstants.StatusText.running : AppConstants.StatusText.stopped)
                metricRow(AppConstants.Labels.recorderObservation, observation?.observedAt ?? AppConstants.StatusText.unknown)
                metricRow(AppConstants.Labels.knownRecorders, "\(observation?.recorders.count ?? 0)")
                metricRow(AppConstants.Labels.knownBeds, "\(observation?.beds.count ?? 0)")
                metricRow(AppConstants.Labels.recorderAnomalies, "\(observation?.anomalies.count ?? 0)")
                metricRow(AppConstants.Labels.runtimeEvents, "\(viewModel.runtimeEvents.events.count)")
            }
        }
    }

    private var anomalySection: some View {
        observationSection(AppConstants.Labels.recorderAnomalies) {
            if anomalyRows.isEmpty {
                emptyObservation(AppConstants.StatusText.noRecorderAnomalies)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(anomalyRows.enumerated()), id: \.offset) { _, anomaly in
                        anomalyRow(anomaly)
                    }
                }
            }
        }
    }

    private var runtimeEventsSection: some View {
        observationSection(AppConstants.Labels.runtimeEvents) {
            DisclosureGroup(isExpanded: $showingRuntimeEvents) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(eventItems) { item in
                        eventRow(item)
                    }
                    if viewModel.runtimeEvents.events.isEmpty {
                        emptyObservation(AppConstants.StatusText.noRuntimeEvents)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("\(viewModel.runtimeEvents.events.count) events")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var observation: VitalDBObservationDocument? {
        viewModel.status.vitalDBObservation
    }

    private var observerStatus: String {
        guard let observation else {
            return AppConstants.StatusText.unavailable
        }
        return observation.ready ? AppConstants.StatusText.ready : AppConstants.StatusText.unhealthy
    }

    private var anomalyRows: [VitalDBAnomalyObservation] {
        observation?.anomalies ?? []
    }

    private var eventItems: [RuntimeEventDisplayPolicy.EventItem] {
        viewModel.runtimeEvents.events.map(eventDisplayPolicy.item)
    }

    private func anomalyRow(_ anomaly: VitalDBAnomalyObservation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(anomaly.severity.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(anomalySeverityColor(anomaly.severity))
                Text(anomaly.kind.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(anomaly.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(anomaly.observedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(anomaly.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func eventRow(_ item: RuntimeEventDisplayPolicy.EventItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.eventType)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(statusColor(item.statusSeverity))
                Spacer()
                Text(item.operation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let detailText = item.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func observationSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
    }

    private func emptyObservation(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    private func anomalySeverityColor(_ severity: VitalDBAnomalySeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        case .unknown:
            return .secondary
        }
    }

    private func statusColor(_ severity: RuntimeEventDisplayPolicy.Severity) -> Color {
        switch severity {
        case .healthy:
            return .green
        case .critical:
            return .red
        case .warning:
            return .orange
        case .neutral:
            return .secondary
        }
    }
}
