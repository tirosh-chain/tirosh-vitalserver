import Contracts
import Foundation
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeBedsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedBedID: String?
    @State private var showingHiddenBeds = false
    @State private var bedSort = RuntimeBedHistoryDisplayPolicy.BedSortOption.name
    @State private var recentlyHiddenBedID: String?
    @State private var bedIDPendingDeletion: String?
    private let displayPolicy = RuntimeVitalRecorderDisplayPolicy()
    private let bedHistoryDisplayPolicy = RuntimeBedHistoryDisplayPolicy()

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
                bedSortPicker
                Toggle("Show hidden", isOn: $showingHiddenBeds)
                    .toggleStyle(.switch)
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionBeds)
                    .font(.headline)
                HStack {
                    bedSearchField
                    bedSortPicker
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

    private var bedSortPicker: some View {
        HStack(spacing: 6) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $bedSort) {
                ForEach(RuntimeBedHistoryDisplayPolicy.BedSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 112)
            .help("Select the Bed list order.")
        }
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
            bedReadIssue
            if case .readFailed(let issue) =
                bedHistoryDisplayPolicy.readPresentation(viewModel.vitalBeds) {
                Text("Bed history read failed: \(issue)")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if filteredBeds.isEmpty {
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
                    .frame(minWidth: 1_400, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
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
                VStack(alignment: .leading, spacing: 0) {
                    selectedBedSummary(bed)
                    Divider()
                    bedMetadata(bed)
                    Divider()
                    linkedRecorderHealth(bed)
                    Divider()
                    bedRelationshipHistory(bed)
                    if bed.visibility == .hidden, showingHiddenBeds {
                        Divider()
                        bedDataManagement(bed)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .alert(
                    "Delete hidden bed?",
                    isPresented: bedDeletionConfirmationPresented
                ) {
                    Button("Cancel", role: .cancel) {
                        bedIDPendingDeletion = nil
                    }
                    Button("Delete", role: .destructive) {
                        guard let bedID = bedIDPendingDeletion else {
                            return
                        }
                        bedIDPendingDeletion = nil
                        Task {
                            recentlyHiddenBedID = nil
                            if await viewModel.deleteVitalDBBed(bedID: bedID) {
                                selectedBedID = nil
                            }
                        }
                    }
                } message: {
                    Text("This removes the hidden bed from retained bed history.")
                }
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
                summaryMetric(AppConstants.Labels.knownBeds, bedSummaryValue(viewModel.vitalBeds.summary.knownBeds))
                summaryMetric(AppConstants.Labels.onlineBeds, bedSummaryValue(viewModel.vitalBeds.summary.onlineBeds))
                summaryMetric(AppConstants.Labels.staleBeds, bedSummaryValue(viewModel.vitalBeds.summary.staleBeds))
                summaryMetric("Assignments", bedSummaryValue(viewModel.vitalBeds.summary.bedAssignments))
                summaryMetric("Events", relationshipEventPageText)
                summaryMetric(AppConstants.Labels.bedAnomalies, bedSummaryValue(viewModel.vitalBeds.summary.bedAnomalies))
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalBeds.updatedAt))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownBeds, bedSummaryValue(viewModel.vitalBeds.summary.knownBeds))
                summaryMetric(AppConstants.Labels.onlineBeds, bedSummaryValue(viewModel.vitalBeds.summary.onlineBeds))
                summaryMetric(AppConstants.Labels.staleBeds, bedSummaryValue(viewModel.vitalBeds.summary.staleBeds))
                summaryMetric("Assignments", bedSummaryValue(viewModel.vitalBeds.summary.bedAssignments))
                summaryMetric("Events", relationshipEventPageText)
                summaryMetric(AppConstants.Labels.bedAnomalies, bedSummaryValue(viewModel.vitalBeds.summary.bedAnomalies))
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalBeds.updatedAt))
            }
        }
    }

    private var filteredBeds: [RuntimeVitalBedRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let beds = showingHiddenBeds
            ? viewModel.vitalBeds.beds
            : viewModel.vitalBeds.beds.filter { $0.visibility != .hidden }
        let filtered = query.isEmpty ? beds : beds.filter { bed in
            [
                bed.bedID,
                bed.name,
                bed.vrcode,
                displayPolicy.recorderSourceText(bed.linkedRecorderVersion),
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
        return bedHistoryDisplayPolicy.sortedBeds(filtered, by: bedSort)
    }

    private var selectedBed: RuntimeVitalBedRecord? {
        guard viewModel.vitalBeds.state != .readFailed,
              let selectedBedID else {
            return nil
        }
        return filteredBeds.first(where: { $0.bedID == selectedBedID })
    }

    private var bedHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader("Status", minWidth: 110)
            tableHeader("Name", minWidth: 170)
            tableHeader("Bed ID", minWidth: 250)
            tableHeader("VRecorder", minWidth: 170)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 140)
            tableHeader("Patient", minWidth: 120)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 190)
            tableHeader("Visibility", minWidth: 100)
        }
        .frame(
            minHeight: RuntimeVitalHistoryTableLayout.headerMinimumHeight,
            alignment: .center
        )
        .padding(10)
    }

    private func bedRow(_ bed: RuntimeVitalBedRecord) -> some View {
        Button {
            selectedBedID = bed.bedID
        } label: {
            HStack(spacing: 12) {
                bedStatusValue(bed.status, minWidth: 110)
                tableValue(
                    reportedText(bed.name, missing: "Bed name not reported"),
                    minWidth: 170,
                    weight: .semibold
                )
                tableValue(bed.bedID, minWidth: 250)
                tableValue(
                    reportedText(bed.vrcode, missing: "VRecorder not reported"),
                    minWidth: 170
                )
                tableValue(
                    viewModel.presentationFormatter.systemTimeAgeText(
                        bed.lastSeenAt
                    ),
                    minWidth: 140
                )
                tableValue(patientText(bed.patientConnected), minWidth: 120)
                tableValue(bedAnomalyText(bed), minWidth: 190)
                tableValue(visibilityText(bed.visibility), minWidth: 100)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            minHeight: RuntimeVitalHistoryTableLayout.rowMinimumHeight,
            alignment: .center
        )
        .padding(10)
        .background(selectedBed?.bedID == bed.bedID ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    private var visibilityActionMessage: some View {
        Group {
            if !viewModel.vitalDBVisibilityActionMessage.isEmpty {
                HStack(spacing: 8) {
                    Text(viewModel.vitalDBVisibilityActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let recentlyHiddenBedID {
                        Button("Undo") {
                            Task {
                                if await viewModel.unhideVitalDBBed(
                                    bedID: recentlyHiddenBedID
                                ) {
                                    selectedBedID = recentlyHiddenBedID
                                    self.recentlyHiddenBedID = nil
                                }
                            }
                        }
                        .disabled(viewModel.isRunningVitalDBVisibilityAction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bedReadIssue: some View {
        if case .partiallyLoaded(let issue) =
            bedHistoryDisplayPolicy.readPresentation(viewModel.vitalBeds) {
            Text("Bed history is partially loaded: \(issue)")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func bedListVisibilityAction(_ bed: RuntimeVitalBedRecord) -> some View {
        if bed.visibility == .hidden {
            Button("Show in list") {
                Task {
                    recentlyHiddenBedID = nil
                    _ = await viewModel.unhideVitalDBBed(bedID: bed.bedID)
                }
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
            .help("Include this bed in the default bed list.")
        } else {
            Button("Hide from list") {
                Task {
                    recentlyHiddenBedID = nil
                    if await viewModel.hideVitalDBBed(bedID: bed.bedID) {
                        recentlyHiddenBedID = bed.bedID
                        selectedBedID = nil
                    }
                }
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
            .help("Remove this bed from the default list without deleting its data.")
        }
    }

    private func selectedBedSummary(_ bed: RuntimeVitalBedRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                bedDetailIdentity(bed)
                Spacer()
                bedListVisibilityAction(bed)
            }
            VStack(alignment: .leading, spacing: 10) {
                bedDetailIdentity(bed)
                bedListVisibilityAction(bed)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bedDetailIdentity(_ bed: RuntimeVitalBedRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(statusColor(bed.status))
                .frame(width: 9, height: 9)
            Text(bed.name ?? bed.bedID)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(statusLabel(bed.status))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(bed.status))
            RuntimeRecorderSourceBadge(version: bed.linkedRecorderVersion)
            if bed.visibility == .hidden {
                Text("Hidden from list")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(Capsule())
            }
        }
    }

    private func bedDataManagement(_ bed: RuntimeVitalBedRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailSectionTitle("Data management")
            Text("Deleting removes this hidden bed from retained bed history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete hidden bed", role: .destructive) {
                bedIDPendingDeletion = bed.bedID
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bedDeletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { bedIDPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    bedIDPendingDeletion = nil
                }
            }
        )
    }

    private func detailSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private func linkedRecorderHealth(_ bed: RuntimeVitalBedRecord) -> some View {
        if let vrcode = displayPolicy.linkedRecorderHealthVrcode(bed) {
            RuntimeRecorderHealthSection(
                viewModel: viewModel,
                vrcode: vrcode,
                recorderSummary: nil,
                title: "Linked Recorder health"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                detailSectionTitle("Linked Recorder health")
                Text("Linked Recorder has not been reported for this Bed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bedMetadata(_ bed: RuntimeVitalBedRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Overview")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow("Bed ID", bed.bedID)
                detailRow("Name", reportedText(bed.name, missing: "Bed name not reported"))
                detailRow("Visibility", visibilityText(bed.visibility))
                detailRow(AppConstants.Labels.patient, patientText(bed.patientConnected))
                detailRow(
                    "First seen",
                    viewModel.presentationFormatter.systemTimeText(bed.firstSeenAt)
                )
                detailRow(
                    AppConstants.Labels.recorderLastSeen,
                    viewModel.presentationFormatter.systemTimeTextWithAge(
                        bed.lastSeenAt
                    )
                )
                detailRow("Latest anomaly", bedAnomalyDetailText(bed))
            }
            detailSectionTitle("Linked Recorder")
                .padding(.top, 4)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow(
                    "VRecorder",
                    reportedText(bed.vrcode, missing: "VRecorder not reported")
                )
                detailRow(
                    AppConstants.Labels.recorderSource,
                    displayPolicy.recorderSourceText(bed.linkedRecorderVersion)
                )
                detailRow(
                    AppConstants.Labels.recorderVersion,
                    reportedText(
                        bed.linkedRecorderVersion,
                        missing: "Version not reported"
                    )
                )
                detailRow("VRecorder status", linkedRecorderStatusText(bed))
                detailRow(
                    "VRecorder IP",
                    reportedText(
                        bed.linkedRecorderIP,
                        missing: bed.vrcode == nil
                            ? "VRecorder not reported"
                            : "VRecorder IP not reported"
                    )
                )
                detailRow(
                    "VRecorder last seen",
                    viewModel.presentationFormatter.systemTimeTextWithAge(
                        bed.linkedRecorderLastSeenAt
                    )
                )
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var relationshipReadIssue: some View {
        switch viewModel.vitalRelationships.state {
        case .loaded:
            if let readError = viewModel.vitalRelationships.readError {
                Text("Relationship history contract issue: \(readError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        case .partiallyLoaded:
            Text(
                "Relationship history is partially loaded: "
                    + (viewModel.vitalRelationships.readError
                        ?? "No failure detail was provided.")
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        case .readFailed:
            Text(
                "Relationship history read failed: "
                    + (viewModel.vitalRelationships.readError
                        ?? "No failure detail was provided.")
            )
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
        bedHistoryDisplayPolicy.relationshipEventPageText(
            viewModel.vitalRelationships
        )
    }

    private func bedSummaryValue(_ value: Int) -> String {
        bedHistoryDisplayPolicy.summaryText(
            value,
            history: viewModel.vitalBeds
        )
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

    private func bedStatusValue(
        _ status: RuntimeVitalBedStatus,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 10, height: 10)
            Text(statusLabel(status))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(status))
                .lineLimit(1)
        }
        .frame(minWidth: minWidth, alignment: .leading)
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
