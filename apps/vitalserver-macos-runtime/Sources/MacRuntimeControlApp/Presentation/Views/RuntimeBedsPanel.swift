import RuntimeControl
import SwiftUI

struct RuntimeBedsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedBedID: String?

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
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionBeds)
                    .font(.headline)
                HStack {
                    bedSearchField
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
            if filteredBeds.isEmpty {
                Text(AppConstants.StatusText.noBedObservations)
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
                    .frame(minWidth: 760, alignment: .leading)
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
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalRecorders.beds.count)")
                summaryMetric(AppConstants.Labels.onlineBeds, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleBeds, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric(AppConstants.Labels.bedAnomalies, "\(viewModel.vitalRecorders.beds.reduce(0) { $0 + $1.currentAnomalyCount })")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalRecorders.beds.count)")
                summaryMetric(AppConstants.Labels.onlineBeds, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleBeds, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric(AppConstants.Labels.bedAnomalies, "\(viewModel.vitalRecorders.beds.reduce(0) { $0 + $1.currentAnomalyCount })")
            }
        }
    }

    private var filteredBeds: [RuntimeVitalBedRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return viewModel.vitalRecorders.beds
        }
        return viewModel.vitalRecorders.beds.filter { bed in
            [
                bed.bedID,
                bed.name,
                bed.vrcode,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var selectedBed: RuntimeVitalBedRecord? {
        if let selectedBedID,
           let bed = viewModel.vitalRecorders.beds.first(where: { $0.bedID == selectedBedID }) {
            return bed
        }
        return filteredBeds.first
    }

    private var linkedRecorder: RuntimeVitalRecorderRecord? {
        guard let vrcode = selectedBed?.vrcode else {
            return nil
        }
        return viewModel.vitalRecorders.recorders.first { $0.vrcode == vrcode }
    }

    private var bedHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader("Bed ID", minWidth: 160)
            tableHeader("Name", minWidth: 140)
            tableHeader("VRecorder", minWidth: 140)
            tableHeader(AppConstants.Labels.recorderStatus, minWidth: 90)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 180)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 70)
        }
        .padding(10)
    }

    private func bedRow(_ bed: RuntimeVitalBedRecord) -> some View {
        Button {
            selectedBedID = bed.bedID
        } label: {
            HStack(spacing: 12) {
                tableValue(bed.bedID, minWidth: 160, weight: .semibold)
                tableValue(bed.name ?? AppConstants.StatusText.unknown, minWidth: 140)
                tableValue(bed.vrcode ?? AppConstants.StatusText.unknown, minWidth: 140)
                Text(bed.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(bed.status))
                    .frame(minWidth: 90, alignment: .leading)
                tableValue(viewModel.presentationFormatter.systemTimeText(bed.lastSeenAt), minWidth: 180)
                tableValue(bed.currentAnomalyCount == 0 ? "-" : "\(bed.currentAnomalyCount)", minWidth: 70)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(selectedBed?.bedID == bed.bedID ? Color.accentColor.opacity(0.10) : Color.clear)
        }
        .buttonStyle(.plain)
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
            Text(bed.status.rawValue.capitalized)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(bed.status))
            Spacer()
            Text(viewModel.presentationFormatter.systemTimeText(bed.lastSeenAt))
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
            detailRow("Name", bed.name ?? AppConstants.StatusText.unknown)
            detailRow("VRecorder", bed.vrcode ?? AppConstants.StatusText.unknown)
            detailRow("VRecorder status", linkedRecorder?.status.rawValue.capitalized ?? AppConstants.StatusText.unknown)
            detailRow("VRecorder IP", linkedRecorder?.lastIP ?? AppConstants.StatusText.unknown)
            detailRow(AppConstants.Labels.patient, patientText(bed.patientConnected))
            detailRow("First seen", viewModel.presentationFormatter.systemTimeText(bed.firstSeenAt))
            detailRow(AppConstants.Labels.recorderLastSeen, viewModel.presentationFormatter.systemTimeText(bed.lastSeenAt))
            detailRow(AppConstants.Labels.observations, "\(bed.observationCount)")
            detailRow(AppConstants.Labels.bedAnomalies, "\(bed.currentAnomalyCount)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bedRelationshipHistory(_ bed: RuntimeVitalBedRecord) -> some View {
        let assignments = viewModel.vitalRelationships.assignments
            .filter { $0.bedID == bed.bedID }
            .prefix(8)
        let events = viewModel.vitalRelationships.events
            .filter { $0.bedID == bed.bedID }
            .prefix(8)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Relationship history")
                .font(.subheadline)
                .fontWeight(.semibold)
            if assignments.isEmpty, events.isEmpty {
                Text("No bed relationship history has been observed.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                if !assignments.isEmpty {
                    relationshipSubsection("Assignments")
                    ForEach(Array(assignments)) { assignment in
                        relationshipRow(
                            title: assignment.vrcode,
                            detail: "\(viewModel.presentationFormatter.systemTimeText(assignment.startedAt)) - \(viewModel.presentationFormatter.systemTimeText(assignment.endedAt))",
                            trailing: assignment.status.rawValue.capitalized
                        )
                    }
                }
                if !events.isEmpty {
                    relationshipSubsection("Events")
                    ForEach(Array(events)) { event in
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
        viewModel.vitalRecorders.beds.filter { $0.status == status }.count
    }

    private func statusColor(_ status: RuntimeVitalBedStatus) -> Color {
        switch status {
        case .online:
            return .green
        case .stale:
            return .orange
        case .offline:
            return .secondary
        case .unknown:
            return .secondary
        }
    }

    private func patientText(_ connected: Bool?) -> String {
        guard let connected else {
            return AppConstants.StatusText.unknown
        }
        return connected ? "Connected" : "Not connected"
    }
}
