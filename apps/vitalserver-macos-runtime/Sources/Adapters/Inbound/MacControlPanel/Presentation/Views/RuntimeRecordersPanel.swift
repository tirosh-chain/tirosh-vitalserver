import Contracts
import Foundation
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeRecordersPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedVrcode: String?
    @State private var showingRecorderHistory = false
    @State private var recorderSort = RuntimeVitalRecorderDisplayPolicy.RecorderSortOption.vrcode
    @State private var activityBucketInterval = RecorderActivityBucketInterval.oneMinute
    @State private var activityPeriod = RecorderActivityPeriod.lastHour
    @State private var activityAllSamplesPageIndex: Int?
    private let activityChartDataBuilder = RuntimeRecorderActivityChartDataBuilder()
    private let displayPolicy = RuntimeVitalRecorderDisplayPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            recorderList
            recorderDetails
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(AppConstants.Labels.sectionRecorders)
                    .font(.headline)
                Spacer()
                recorderSearchField
                recorderSortPicker
                Toggle("History", isOn: $showingRecorderHistory)
                    .toggleStyle(.switch)
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionRecorders)
                    .font(.headline)
                HStack {
                    recorderSearchField
                    recorderSortPicker
                    Toggle("History", isOn: $showingRecorderHistory)
                        .toggleStyle(.switch)
                    refreshButton
                    Spacer()
                }
            }
        }
    }

    private var recorderList: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryMetrics
            if filteredRecorders.isEmpty {
                Text(AppConstants.StatusText.noVitalRecorderData)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        recorderHeaderRow
                        ForEach(filteredRecorders) { recorder in
                            Divider()
                            recorderRow(recorder)
                        }
                    }
                    .frame(minWidth: 850, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var recorderDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.recorderDetails)
                .font(.headline)
            if let recorder = selectedRecorder {
                selectedRecorderSummary(recorder)
                recorderActivity(recorder)
                recorderMetadata(recorder)
                recorderRelationshipHistory(recorder)
            } else {
                Text("Select a VRecorder to view activity.")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var recorderSearchField: some View {
        TextField(AppConstants.Labels.recorderSearch, text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
    }

    private var recorderSortPicker: some View {
        HStack(spacing: 6) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $recorderSort) {
                ForEach(RuntimeVitalRecorderDisplayPolicy.RecorderSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 112)
            .help("Select the VRecorder list order.")
        }
    }

    private var refreshButton: some View {
        Button(AppConstants.Actions.refresh) {
            Task {
                await viewModel.refreshVitalRecorders()
            }
        }
    }

    private var summaryMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
                summaryMetric("Current", "\(currentRecorders.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(currentRecorders.reduce(0) { $0 + $1.currentAnomalyCount })")
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalRecorders.updatedAt))
            }
            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
                summaryMetric("Current", "\(currentRecorders.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(currentRecorders.reduce(0) { $0 + $1.currentAnomalyCount })")
                summaryMetric("Data updated", viewModel.presentationFormatter.systemTimeText(viewModel.vitalRecorders.updatedAt))
            }
        }
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 12)]
    }

    private var filteredRecorders: [RuntimeVitalRecorderRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return visibleRecorders
        }
        return visibleRecorders.filter { recorder in
            [
                recorder.vrcode,
                recorder.lastIP,
                recorder.version,
                recorder.bedID,
                recorder.bedName,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var currentRecorders: [RuntimeVitalRecorderRecord] {
        viewModel.vitalRecorders.recorders.filter(\.presentInLatestObservation)
    }

    private var visibleRecorders: [RuntimeVitalRecorderRecord] {
        let recorders = showingRecorderHistory ? viewModel.vitalRecorders.recorders : currentRecorders
        return displayPolicy.sortedRecorders(recorders, by: recorderSort)
    }

    private var selectedRecorder: RuntimeVitalRecorderRecord? {
        if let selectedVrcode,
           let recorder = visibleRecorders.first(where: { $0.vrcode == selectedVrcode }) {
            return recorder
        }
        return filteredRecorders.first ?? visibleRecorders.first
    }

    private var recorderHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader("VRecorder", minWidth: 120)
            tableHeader(AppConstants.Labels.recorderStatus, minWidth: 80)
            tableHeader("IP", minWidth: 120)
            tableHeader(AppConstants.Labels.bed, minWidth: 120)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 220)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 130)
        }
        .padding(10)
    }

    private func recorderRow(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        Button {
            selectedVrcode = recorder.vrcode
        } label: {
            HStack(spacing: 12) {
                tableValue(recorder.vrcode, minWidth: 120, weight: .semibold)
                Text(statusLabel(recorder.status))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(recorder.status))
                    .frame(minWidth: 80, alignment: .leading)
                tableValue(reportedText(recorder.lastIP, missing: "IP not reported"), minWidth: 120)
                tableValue(reportedText(recorder.bedName ?? recorder.bedID, missing: "Bed not reported"), minWidth: 120)
                tableValue(viewModel.presentationFormatter.systemTimeTextWithAge(recorder.lastSeenAt), minWidth: 220)
                tableValue(recorderAnomalyText(recorder), minWidth: 130)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(selectedRecorder?.vrcode == recorder.vrcode ? Color.accentColor.opacity(0.10) : Color.clear)
        }
        .buttonStyle(.plain)
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

    private func selectedRecorderSummary(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(statusColor(recorder.status))
                .frame(width: 9, height: 9)
            Text(recorder.vrcode)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(statusLabel(recorder.status))
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(recorder.status))
            Spacer()
            Text(viewModel.presentationFormatter.systemTimeText(recorder.lastSeenAt))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recorderActivity(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        let activityQuery = recorderActivityWindowQuery(for: recorder)
        let activityWindow = viewModel.recorderActivityWindow(query: activityQuery)
        let activityDisplay = activityChartDataBuilder.display(from: activityWindow)
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text("Activity")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if activityDisplay.state.showsControls || activityWindow == nil {
                        activityControls
                    }
                    if let latestSample = activityDisplay.latestSample {
                        Text("Last activity \(viewModel.presentationFormatter.systemTimeText(latestSample.observedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack(spacing: 12) {
                        if activityDisplay.state.showsControls || activityWindow == nil {
                            activityControls
                        }
                        if let latestSample = activityDisplay.latestSample {
                            Text("Last activity \(viewModel.presentationFormatter.systemTimeText(latestSample.observedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
            }

            if activityWindow == nil {
                Text("Loading recorder activity window...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                switch activityDisplay.state {
            case .readFailed(let readError):
                Text("Recorder activity history read issue: \(readError)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            case .notReported:
                Text("Recorder activity history is not reported.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            case .emptyTimeline:
                Text("No recent data activity has been observed for this VRecorder.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            case .noBucketsInPeriod:
                Text("No data activity has been observed in the selected period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            case .invalidTimeline(let timestamp):
                Text("Recorder activity history has an invalid timestamp: \(timestamp)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            case .available:
                RecorderActivityChart(
                    buckets: activityDisplay.buckets,
                    intervalTitle: activityBucketInterval.title
                )
                    .frame(height: 190)
                if let allSamplesWindow = activityDisplay.allSamplesWindow {
                    activityAllSamplesWindowControl(allSamplesWindow)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        activityMetric("Packets", activityDisplay.latestBucket.map { "\($0.messageCount)" } ?? "-")
                        activityMetric("Total packets", activityDisplay.totalPackets.map(String.init) ?? "-")
                        activityMetric("Data rate", activityDisplay.latestBucketBytesPerSecond.map(formatBytesPerSecond) ?? "-")
                        activityMetric("Room entries", activityDisplay.latestBucket.map { "\($0.roomCount)" } ?? "-")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], alignment: .leading, spacing: 8) {
                        activityMetric("Packets", activityDisplay.latestBucket.map { "\($0.messageCount)" } ?? "-")
                        activityMetric("Total packets", activityDisplay.totalPackets.map(String.init) ?? "-")
                        activityMetric("Data rate", activityDisplay.latestBucketBytesPerSecond.map(formatBytesPerSecond) ?? "-")
                        activityMetric("Room entries", activityDisplay.latestBucket.map { "\($0.roomCount)" } ?? "-")
                    }
                }
                }
            }
        }
        .task(id: recorderActivityWindowTaskID(activityQuery)) {
            await viewModel.refreshVitalRecorderActivityWindow(query: activityQuery)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recorderActivityWindowQuery(
        for recorder: RuntimeVitalRecorderRecord
    ) -> RuntimeVitalRecorderActivityWindowQuery {
        RuntimeVitalRecorderActivityWindowQuery(
            vrcode: recorder.vrcode,
            bucketSeconds: activityBucketInterval.seconds,
            period: activityPeriod.windowPeriod,
            pageIndex: activityPeriod == .all ? activityAllSamplesPageIndex : nil
        )
    }

    private func recorderActivityWindowTaskID(
        _ query: RuntimeVitalRecorderActivityWindowQuery
    ) -> String {
        [
            query.vrcode,
            "\(query.bucketSeconds)",
            query.period.rawValue,
            query.pageIndex.map(String.init) ?? "latest",
        ].joined(separator: "|")
    }

    private var activityControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                activityPeriodPicker
                activityBucketPicker
            }
            VStack(alignment: .leading, spacing: 8) {
                activityPeriodPicker
                activityBucketPicker
            }
        }
    }

    private var activityPeriodPicker: some View {
        HStack(spacing: 6) {
            Text("Window")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: activityPeriodSelection) {
                ForEach(RecorderActivityPeriod.allCases) { period in
                    Text(period.title)
                        .tag(period)
                        .disabled(!period.isEnabled(for: activityBucketInterval))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 124)
            .help("Select the activity window shown in the chart.")
        }
    }

    private var activityBucketPicker: some View {
        HStack(spacing: 6) {
            Text("Bucket")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: activityBucketSelection) {
                ForEach(RecorderActivityBucketInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .help("Group packet activity by this interval.")
        }
    }

    private var activityPeriodSelection: Binding<RecorderActivityPeriod> {
        Binding(
            get: { activityPeriod },
            set: { period in
                guard period.isEnabled(for: activityBucketInterval) else {
                    return
                }
                activityPeriod = period
                activityAllSamplesPageIndex = nil
            }
        )
    }

    private var activityBucketSelection: Binding<RecorderActivityBucketInterval> {
        Binding(
            get: { activityBucketInterval },
            set: { interval in
                activityBucketInterval = interval
                activityAllSamplesPageIndex = nil
                if !activityPeriod.isEnabled(for: interval) {
                    activityPeriod = .last6Hours
                }
            }
        )
    }

    private func activityAllSamplesWindowControl(_ window: RecorderActivityAllSamplesWindow) -> some View {
        let pageCount = max(window.pageCount, 1)
        let pageIndex = min(max(window.pageIndex, 0), pageCount - 1)
        let maxPageIndex = pageCount - 1
        let pageBinding = Binding<Double>(
            get: {
                Double(min(max(activityAllSamplesPageIndex ?? pageIndex, 0), maxPageIndex))
            },
            set: { value in
                activityAllSamplesPageIndex = min(max(Int(value.rounded()), 0), maxPageIndex)
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(activityAllSamplesWindowText(window))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(pageIndex + 1) / \(pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if pageCount > 1 {
                Slider(
                    value: pageBinding,
                    in: 0...Double(maxPageIndex),
                    step: 1
                )
            }
        }
    }

    private func activityAllSamplesWindowText(_ window: RecorderActivityAllSamplesWindow) -> String {
        guard let startedAt = window.windowStartedAt,
              let endedAt = window.windowEndedAt else {
            return "No activity window"
        }
        return "\(viewModel.presentationFormatter.systemTimeText(startedAt)) - \(viewModel.presentationFormatter.systemTimeText(endedAt))"
    }

    private func recorderMetadata(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            detailRow("IP", reportedText(recorder.lastIP, missing: "IP not reported"))
            detailRow(AppConstants.Labels.recorderVersion, reportedText(recorder.version, missing: "Version not reported"))
            detailRow(AppConstants.Labels.bed, reportedText(recorder.bedName ?? recorder.bedID, missing: "Bed not reported"))
            detailRow("Bed ID", reportedText(linkedBed(for: recorder)?.bedID ?? recorder.bedID, missing: "Bed ID not reported"))
            detailRow(AppConstants.Labels.patient, patientText(recorder.patientConnected))
            detailRow("First seen", viewModel.presentationFormatter.systemTimeText(recorder.firstSeenAt))
            detailRow(AppConstants.Labels.recorderLastSeen, viewModel.presentationFormatter.systemTimeTextWithAge(recorder.lastSeenAt))
            detailRow("Latest anomaly", recorderAnomalyDetailText(recorder))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recorderRelationshipHistory(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        let assignments = viewModel.vitalRelationships.assignments
            .filter { $0.vrcode == recorder.vrcode }
            .prefix(8)
        let events = viewModel.vitalRelationships.events
            .filter { $0.vrcode == recorder.vrcode || $0.previousVrcode == recorder.vrcode }
            .prefix(8)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Relationship history")
                .font(.subheadline)
                .fontWeight(.semibold)
            relationshipReadIssue
            if assignments.isEmpty, events.isEmpty, viewModel.vitalRelationships.state == .loaded {
                Text("No recorder relationship history has been observed.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if viewModel.vitalRelationships.state != .readFailed {
                if !assignments.isEmpty {
                    relationshipSubsection("Assignments")
                    ForEach(Array(assignments)) { assignment in
                        relationshipRow(
                            title: assignment.bedName ?? assignment.bedID,
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

    private func activityMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
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

    private func count(_ status: RuntimeVitalRecorderStatus) -> Int {
        currentRecorders.filter { $0.status == status }.count
    }

    private func recorderAnomalyText(_ recorder: RuntimeVitalRecorderRecord) -> String {
        displayPolicy.recorderAnomalyText(recorder)
    }

    private func recorderAnomalyDetailText(_ recorder: RuntimeVitalRecorderRecord) -> String {
        displayPolicy.anomalyDetailText(
            kind: recorder.latestAnomalyKind,
            severity: recorder.latestAnomalySeverity,
            message: recorder.latestAnomalyMessage,
            count: recorder.currentAnomalyCount
        )
    }

    private func statusColor(_ status: RuntimeVitalRecorderStatus) -> Color {
        switch displayPolicy.statusTone(status) {
        case .active:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return .secondary
        }
    }

    private func statusLabel(_ status: RuntimeVitalRecorderStatus) -> String {
        displayPolicy.statusText(status)
    }

    private func linkedBed(for recorder: RuntimeVitalRecorderRecord) -> RuntimeVitalBedRecord? {
        if let bedID = recorder.bedID,
           let bed = viewModel.vitalRecorders.beds.first(where: { $0.bedID == bedID }) {
            return bed
        }
        return viewModel.vitalRecorders.beds.first { $0.vrcode == recorder.vrcode }
    }

    private func patientText(_ connected: Bool?) -> String {
        displayPolicy.patientText(connected)
    }

    private func reportedText(_ value: String?, missing: String) -> String {
        displayPolicy.reportedText(value, missing: missing)
    }

    private func formatBytesPerSecond(_ value: Double) -> String {
        displayPolicy.bytesPerSecondText(value)
    }

}
