import Contracts
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeBedsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedBedID: String?
    @State private var showingHiddenBeds = false
    private let displayPolicy = RuntimeVitalRecorderDisplayPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bedList
            bedDetails
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(AppConstants.Labels.sectionBeds)
                    .font(.headline)
                Spacer()
                bedSearchField
                Toggle("Show hidden", isOn: $showingHiddenBeds)
                    .toggleStyle(.switch)
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionBeds)
                    .font(.headline)
                HStack {
                    bedSearchField
                    Toggle("Show hidden", isOn: $showingHiddenBeds)
                        .toggleStyle(.switch)
                    refreshButton
                    Spacer()
                }
            }
        }
    }

    private var bedSearchField: some View {
        TextField(AppConstants.Labels.bedSearch, text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
    }

    private var refreshButton: some View {
        Button(AppConstants.Actions.refresh) {
            Task {
                await viewModel.refreshVitalRecorders()
            }
        }
    }

    private var bedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryMetrics
            visibilityActionMessage
            if filteredBeds.isEmpty {
                Text(AppConstants.StatusText.noBedData)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        bedHeaderRow
                        ForEach(filteredBeds) { bed in
                            Divider()
                            bedRow(bed)
                        }
                    }
                    .frame(minWidth: 1200, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var bedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.bedDetails)
                .font(.headline)
            if let bed = selectedBed {
                selectedBedSummary(bed)
                bedMetadata(bed)
                bedRelationshipHistory(bed)
            } else {
                Text(AppConstants.StatusText.selectBed)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var summaryMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalBeds.beds.count)")
                summaryMetric(AppConstants.Labels.onlineBeds, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleBeds, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric("Events", relationshipEventPageText)
                summaryMetric(AppConstants.Labels.bedAnomalies, "\(viewModel.vitalBeds.beds.reduce(0) { $0 + $1.currentAnomalyCount })")
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalBeds.updatedAt))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalBeds.beds.count)")
                summaryMetric(AppConstants.Labels.onlineBeds, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleBeds, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric("Events", relationshipEventPageText)
                summaryMetric(AppConstants.Labels.bedAnomalies, "\(viewModel.vitalBeds.beds.reduce(0) { $0 + $1.currentAnomalyCount })")
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalBeds.updatedAt))
            }
        }
    }

    private var filteredBeds: [RuntimeVitalBedRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let beds = showingHiddenBeds
            ? viewModel.vitalBeds.beds
            : viewModel.vitalBeds.beds.filter { $0.visibility != .hidden }
        guard !query.isEmpty else {
            return beds
        }
        return beds.filter { bed in
            [
                bed.bedID,
                bed.name,
                bed.vrcode,
                displayPolicy.recorderSourceText(bed.linkedRecorderVersion),
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var selectedBed: RuntimeVitalBedRecord? {
        if let selectedBedID,
           let bed = filteredBeds.first(where: { $0.bedID == selectedBedID }) {
            return bed
        }
        return filteredBeds.first
    }

    private var bedHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader("Bed ID", minWidth: 160)
            tableHeader("Name", minWidth: 140)
            tableHeader("VRecorder", minWidth: 140)
            tableHeader(AppConstants.Labels.recorderStatus, minWidth: 90)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 220)
            tableHeader("Visibility", minWidth: 80)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 130)
            tableHeader("Actions", minWidth: 160)
        }
        .padding(10)
    }

    private func bedRow(_ bed: RuntimeVitalBedRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedBedID = bed.bedID
            } label: {
                HStack(spacing: 12) {
                    tableValue(bed.bedID, minWidth: 160, weight: .semibold)
                    tableValue(reportedText(bed.name, missing: "Bed name not reported"), minWidth: 140)
                    tableValue(reportedText(bed.vrcode, missing: "VRecorder not reported"), minWidth: 140)
                    Text(statusLabel(bed.status))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor(bed.status))
                        .frame(minWidth: 90, alignment: .leading)
                    tableValue(viewModel.presentationFormatter.systemTimeTextWithAge(bed.lastSeenAt), minWidth: 220)
                    tableValue(visibilityText(bed.visibility), minWidth: 80)
                    tableValue(bedAnomalyText(bed), minWidth: 130)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            bedActionButtons(bed)
        }
        .padding(10)
        .background(selectedBed?.bedID == bed.bedID ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    private var visibilityActionMessage: some View {
        Group {
            if !viewModel.vitalDBVisibilityActionMessage.isEmpty {
                Text(viewModel.vitalDBVisibilityActionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bedActionButtons(_ bed: RuntimeVitalBedRecord) -> some View {
        HStack(spacing: 6) {
            if bed.visibility == .hidden {
                Button("Unhide") {
                    Task {
                        await viewModel.unhideVitalDBBed(bedID: bed.bedID)
                    }
                }
                .disabled(viewModel.isRunningVitalDBVisibilityAction)
                if showingHiddenBeds {
                    Button("Delete") {
                        Task {
                            await viewModel.deleteVitalDBBed(bedID: bed.bedID)
                        }
                    }
                    .disabled(viewModel.isRunningVitalDBVisibilityAction)
                }
            } else {
                Button("Hide") {
                    Task {
                        await viewModel.hideVitalDBBed(bedID: bed.bedID)
                    }
                }
                .disabled(viewModel.isRunningVitalDBVisibilityAction)
            }
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private func selectedBedSummary(_ bed: RuntimeVitalBedRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(statusColor(bed.status))
                .frame(width: 9, height: 9)
            Text(bed.name ?? bed.bedID)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(statusLabel(bed.status))
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(bed.status))
            RuntimeRecorderSourceBadge(version: bed.linkedRecorderVersion)
            Spacer()
            Text(viewModel.presentationFormatter.systemTimeTextWithAge(bed.lastSeenAt))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bedMetadata(_ bed: RuntimeVitalBedRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            detailRow("Bed ID", bed.bedID)
            detailRow("Name", reportedText(bed.name, missing: "Bed name not reported"))
            detailRow("VRecorder", reportedText(bed.vrcode, missing: "VRecorder not reported"))
            detailRow(AppConstants.Labels.recorderSource, displayPolicy.recorderSourceText(bed.linkedRecorderVersion))
            detailRow("Visibility", visibilityText(bed.visibility))
            detailRow(
                "VRecorder status",
                linkedRecorderStatusText(bed)
            )
            detailRow(
                "VRecorder IP",
                reportedText(bed.linkedRecorderIP, missing: bed.vrcode == nil ? "VRecorder not reported" : "VRecorder IP not reported")
            )
            detailRow("VRecorder last seen", viewModel.presentationFormatter.systemTimeTextWithAge(bed.linkedRecorderLastSeenAt))
            detailRow(AppConstants.Labels.patient, patientText(bed.patientConnected))
            detailRow("First seen", viewModel.presentationFormatter.systemTimeText(bed.firstSeenAt))
            detailRow(AppConstants.Labels.recorderLastSeen, viewModel.presentationFormatter.systemTimeTextWithAge(bed.lastSeenAt))
            detailRow("Latest anomaly", bedAnomalyDetailText(bed))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bedRelationshipHistory(_ bed: RuntimeVitalBedRecord) -> some View {
        let history = viewModel.relationshipPresentationHistory(bedID: bed.bedID)
        let assignments = history.assignments
        let events = history.events

        return VStack(alignment: .leading, spacing: 10) {
            Text("Relationship history")
                .font(.subheadline)
                .fontWeight(.semibold)
            relationshipReadIssue
            if assignments.isEmpty, events.isEmpty, viewModel.vitalRelationships.state == .loaded {
                Text("No bed relationship history has been observed.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if viewModel.vitalRelationships.state != .readFailed {
                if !assignments.isEmpty {
                    relationshipSubsection("Assignments")
                    ForEach(assignments) { assignment in
                        relationshipRow(
                            title: assignment.vrcode,
                            detail: "\(viewModel.presentationFormatter.systemTimeText(assignment.startedAt)) - \(viewModel.presentationFormatter.systemTimeText(assignment.endedAt))",
                            trailing: assignment.status.rawValue.capitalized
                        )
                    }
                }
                if !events.isEmpty {
                    relationshipSubsection("Events")
                    ForEach(events) { event in
                        relationshipRow(
                            title: "\(event.severity.rawValue.capitalized) · \(event.eventType.rawValue)",
                            detail: event.message,
                            trailing: viewModel.presentationFormatter.systemTimeText(event.observedAt)
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var relationshipReadIssue: some View {
        if let readError = viewModel.vitalRelationships.readError {
            Text("Relationship history read issue: \(readError)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func relationshipSubsection(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func relationshipRow(title: String, detail: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(trailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    private var relationshipEventPageText: String {
        "\(viewModel.vitalRelationships.events.count) of \(viewModel.vitalRelationships.eventTotalCount)"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
    }

    private func tableHeader(_ text: String, minWidth: CGFloat) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(minWidth: minWidth, alignment: .leading)
    }

    private func tableValue(_ text: String, minWidth: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(weight)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(minWidth: minWidth, alignment: .leading)
    }

    private func count(_ status: RuntimeVitalBedStatus) -> Int {
        viewModel.vitalBeds.beds.filter { $0.status == status }.count
    }

    private func bedAnomalyText(_ bed: RuntimeVitalBedRecord) -> String {
        displayPolicy.bedAnomalyText(bed)
    }

    private func bedAnomalyDetailText(_ bed: RuntimeVitalBedRecord) -> String {
        displayPolicy.anomalyDetailText(
            kind: bed.latestAnomalyKind,
            severity: bed.latestAnomalySeverity,
            message: bed.latestAnomalyMessage,
            count: bed.currentAnomalyCount
        )
    }

    private func linkedRecorderStatusText(_ bed: RuntimeVitalBedRecord) -> String {
        guard let status = bed.linkedRecorderStatus else {
            return bed.vrcode == nil ? "VRecorder not reported" : "VRecorder status not reported"
        }
        return displayPolicy.statusText(status)
    }

    private func statusColor(_ status: RuntimeVitalBedStatus) -> Color {
        switch displayPolicy.statusTone(status) {
        case .active:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return .secondary
        }
    }

    private func statusLabel(_ status: RuntimeVitalBedStatus) -> String {
        displayPolicy.statusText(status)
    }

    private func visibilityText(_ visibility: RuntimeVitalRecordVisibility) -> String {
        switch visibility {
        case .visible:
            return "Visible"
        case .hidden:
            return "Hidden"
        }
    }

    private func patientText(_ connected: Bool?) -> String {
        displayPolicy.patientText(connected)
    }

    private func reportedText(_ value: String?, missing: String) -> String {
        displayPolicy.reportedText(value, missing: missing)
    }
}
