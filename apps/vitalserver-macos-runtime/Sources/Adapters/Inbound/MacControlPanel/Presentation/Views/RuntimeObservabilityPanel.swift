import Contracts
import SwiftUI
import Errors

struct RuntimeObservabilityPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var showingRecorderAnomalies = true

    private let eventDisplayPolicy = RuntimeEventDisplayPolicy()
    private let runtimeEventLimitOptions = [25, 50, 100, 200, 500]
    private let runtimeEventPeriodOptions = RuntimeEventPeriodOption.allCases
    private let runtimeEventFilterOptions = RuntimeEventFilterOption.allOptions

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
                Task {
                    await viewModel.refreshRuntimeEvents()
                    await viewModel.refreshVitalRecorders()
                }
            }
        }
    }

    private var pipelineSection: some View {
        observationSection("Observation pipeline") {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                metricRow(AppConstants.Labels.vitalDBObserver, observerStatus)
                metricRow(AppConstants.Labels.guestLogSyncService, guestLogSyncStatus)
                metricRow(AppConstants.Labels.recorderObservation, observationTimeText(observation?.observedAt))
                metricRow(AppConstants.Labels.knownRecorders, observationMetricText(observation?.recorders.count))
                metricRow(AppConstants.Labels.knownBeds, observationMetricText(observation?.beds.count))
                metricRow(AppConstants.Labels.recorderAnomalies, observationMetricText(observation?.anomalies.count))
                metricRow("Runtime events (24h)", "\(viewModel.runtimeEventsLast24HoursCount)")
            }
        }
    }

    private var anomalySection: some View {
        observationSection(AppConstants.Labels.recorderAnomalies) {
            vitalDBObservationReadIssue
            if observation == nil {
                emptyObservation(AppConstants.StatusText.noVitalRecorderData)
            } else if anomalyRows.isEmpty {
                emptyObservation(AppConstants.StatusText.noRecorderAnomalies)
            } else {
                RuntimeDisclosureSection(isExpanded: $showingRecorderAnomalies) {
                    Text("\(anomalyRows.count) anomalies")
                        .foregroundStyle(.secondary)
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(anomalyRows.enumerated()), id: \.offset) { _, anomaly in
                            anomalyRow(anomaly)
                        }
                    }
                }
            }
        }
    }

    private var guestLogSyncStatus: String {
        switch viewModel.status.guestLogSyncServiceState {
        case .loaded:
            return AppConstants.StatusText.running
        case .notLoaded:
            return AppConstants.StatusText.stopped
        case .readFailed, .permissionDenied, .unknown, nil:
            return AppConstants.StatusText.unavailable
        }
    }

    private var runtimeEventsSection: some View {
        observationSection(AppConstants.Labels.runtimeEvents) {
            VStack(alignment: .leading, spacing: 10) {
                runtimeEventControls
                runtimeEventReadIssue
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(eventItems) { item in
                            eventRow(item)
                        }
                        if eventItems.isEmpty, viewModel.runtimeEvents.state == .loaded {
                            emptyObservation(AppConstants.StatusText.noRuntimeEvents)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
            }
        }
    }

    @ViewBuilder
    private var vitalDBObservationReadIssue: some View {
        if let readError = viewModel.vitalDBObservationSnapshot.readError {
            Text("VitalDB observation read issue: \(readError)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var runtimeEventReadIssue: some View {
        if let readError = viewModel.runtimeEvents.readError {
            Text("Runtime event read issue: \(readError)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var runtimeEventControls: some View {
        HStack(spacing: 12) {
            runtimeEventPeriodControl
            runtimeEventFilterControl
            runtimeEventLimitControl
            Spacer(minLength: 0)
            Text(runtimeEventSummaryText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var runtimeEventPeriodControl: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.runtimeEventPeriod)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: $viewModel.runtimeEventPeriod) {
                ForEach(runtimeEventPeriodOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .frame(width: 170)
            .labelsHidden()
            .onChange(of: viewModel.runtimeEventPeriod) { _ in
                Task { await viewModel.refreshRuntimeEvents() }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var runtimeEventFilterControl: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.runtimeEventFilter)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: $viewModel.runtimeEventFilter) {
                ForEach(runtimeEventFilterOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .frame(width: 230)
            .labelsHidden()
            .onChange(of: viewModel.runtimeEventFilter) { _ in
                Task { await viewModel.refreshRuntimeEvents() }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var runtimeEventLimitControl: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.runtimeEventLimit)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: $viewModel.runtimeEventLimit) {
                ForEach(runtimeEventLimitOptions, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
            .frame(width: 100)
            .labelsHidden()
            .onChange(of: viewModel.runtimeEventLimit) { _ in
                Task { await viewModel.refreshRuntimeEvents() }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var observation: VitalDBObservationDocument? {
        switch viewModel.vitalDBObservationSnapshot.state {
        case .loaded:
            return viewModel.vitalDBObservationSnapshot.observation
        case .failed:
            return nil
        case .unavailable:
            return nil
        }
    }

    private var observerStatus: String {
        guard let observation else {
            return AppConstants.StatusText.unavailable
        }
        return observation.ready ? AppConstants.StatusText.ready : AppConstants.StatusText.unhealthy
    }

    private var anomalyRows: [VitalDBAnomalyObservation] {
        (observation?.anomalies ?? [])
            .sorted { lhs, rhs in
                if lhs.severity == rhs.severity {
                    return lhs.observedAt > rhs.observedAt
                }
                return anomalySeverityRank(lhs.severity) > anomalySeverityRank(rhs.severity)
            }
    }

    private var eventItems: [RuntimeEventDisplayPolicy.EventItem] {
        viewModel.runtimeEvents.events
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id > rhs.id
                }
                return lhs.timestamp > rhs.timestamp
            }
            .map(eventDisplayPolicy.item)
    }

    private var runtimeEventSummaryText: String {
        guard let matchingCount = viewModel.runtimeEvents.matchingCount else {
            return "\(eventItems.count) events"
        }
        if matchingCount == eventItems.count {
            return "\(eventItems.count) events"
        }
        return "\(eventItems.count) shown · \(matchingCount) matching"
    }

    private func observationTimeText(_ timestamp: String?) -> String {
        viewModel.presentationFormatter.systemTimeText(timestamp)
    }

    private func observationMetricText(_ value: Int?) -> String {
        value.map(String.init) ?? AppConstants.StatusText.notReported
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
                Text(observationTimeText(anomaly.observedAt))
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
                Text(observationTimeText(item.timestamp))
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

    private func anomalySeverityRank(_ severity: VitalDBAnomalySeverity) -> Int {
        switch severity {
        case .critical:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        case .unknown:
            return 0
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

private struct RuntimeEventFilterOption: Identifiable {
    let id: String
    let title: String

    static let allOptions = [all] + RuntimeEventType.knownTypes.map {
        RuntimeEventFilterOption(title: $0.rawValue, eventType: $0)
    }

    static let all = RuntimeEventFilterOption(
        id: "",
        title: AppConstants.StatusText.allRuntimeEvents
    )

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(title: String, eventType: RuntimeEventType) {
        self.id = eventType.rawValue
        self.title = title
    }
}
