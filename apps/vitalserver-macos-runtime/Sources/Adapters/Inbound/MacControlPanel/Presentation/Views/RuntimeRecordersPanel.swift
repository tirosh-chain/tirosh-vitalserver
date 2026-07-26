import Contracts
import Foundation
import RuntimeControl
import SwiftUI
import Errors

struct RuntimeRecorderTableLayout {
    static let headerMinimumHeight: CGFloat = 28
    static let rowMinimumHeight: CGFloat = 52
}

struct RuntimeRecordersPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedVrcode: String?
    @State private var showingRecorderHistory = false
    @State private var showingHiddenRecorders = false
    @State private var recorderSort = RuntimeVitalRecorderDisplayPolicy.RecorderSortOption.vrcode
    @State private var activityBucketInterval = RecorderActivityBucketInterval.oneMinute
    @State private var activityPeriod = RecorderActivityPeriod.lastHour
    @State private var activityAllSamplesPageIndex: Int?
    @State private var recentlyHiddenVrcode: String?
    @State private var recorderVrcodePendingDeletion: String?
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
                Toggle("Show hidden", isOn: $showingHiddenRecorders)
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
                    Toggle("Show hidden", isOn: $showingHiddenRecorders)
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
            visibilityActionMessage
            if filteredRecorders.isEmpty {
                Text(AppConstants.StatusText.noVitalRecorderData)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        recorderHeaderRow
                        ForEach(filteredRecorders) { recorder in
                            Divider()
                            recorderRow(recorder)
                        }
                    }
                    .frame(minWidth: 1280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var recorderDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.recorderDetails)
                .font(.headline)
            if let recorder = selectedRecorder {
                VStack(alignment: .leading, spacing: 0) {
                    selectedRecorderSummary(recorder)
                    Divider()
                    recorderMetadata(recorder)
                    Divider()
                    recorderObservability(recorder)
                    Divider()
                    recorderActivity(recorder)
                    Divider()
                    recorderNetworkAccess(recorder)
                    Divider()
                    recorderRelationshipHistory(recorder)
                    Divider()
                    recorderVitalFiles(recorder)
                    if recorder.visibility == .hidden, showingHiddenRecorders {
                        Divider()
                        recorderDataManagement(recorder)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .alert(
                    "Delete hidden recorder?",
                    isPresented: recorderDeletionConfirmationPresented
                ) {
                    Button("Cancel", role: .cancel) {
                        recorderVrcodePendingDeletion = nil
                    }
                    Button("Delete", role: .destructive) {
                        guard let vrcode = recorderVrcodePendingDeletion else {
                            return
                        }
                        recorderVrcodePendingDeletion = nil
                        Task {
                            recentlyHiddenVrcode = nil
                            if await viewModel.deleteVitalDBRecorder(vrcode: vrcode) {
                                selectedVrcode = nil
                            }
                        }
                    }
                } message: {
                    Text("This removes the hidden recorder from retained recorder history.")
                }
            } else {
                Text("Select a VRecorder to view details.")
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
                displayPolicy.recorderSourceText(recorder.version),
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
        let filtered = showingHiddenRecorders
            ? recorders
            : recorders.filter { $0.visibility != .hidden }
        return displayPolicy.sortedRecorders(filtered, by: recorderSort)
    }

    private var selectedRecorder: RuntimeVitalRecorderRecord? {
        guard let selectedVrcode else {
            return nil
        }
        return filteredRecorders.first(where: { $0.vrcode == selectedVrcode })
    }

    private var recorderHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader(AppConstants.Labels.recorderStatus, minWidth: 110)
            tableHeader("VRecorder", minWidth: 170)
            tableHeader(AppConstants.Labels.bed, minWidth: 180)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 140)
            tableHeader("Device health", minWidth: 220)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 190)
            tableHeader("IP", minWidth: 230)
        }
        .frame(minHeight: RuntimeRecorderTableLayout.headerMinimumHeight, alignment: .center)
        .padding(10)
    }

    private func recorderRow(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedVrcode = recorder.vrcode
            } label: {
                HStack(spacing: 12) {
                    recorderStatusValue(recorder.status, minWidth: 110)
                    tableRecorderIdentity(recorder, minWidth: 170)
                    tableValue(reportedText(recorder.bedName ?? recorder.bedID, missing: "Bed not reported"), minWidth: 180)
                    tableValue(viewModel.presentationFormatter.systemTimeAgeText(recorder.lastSeenAt), minWidth: 140)
                    tableValue(recorderOperationalHealthSummary(recorder.observability), minWidth: 220)
                    tableValue(recorderAnomalyText(recorder), minWidth: 190)
                    tableIPValue(recorder, minWidth: 230)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: RuntimeRecorderTableLayout.rowMinimumHeight, alignment: .center)
        .padding(10)
        .background(selectedRecorder?.vrcode == recorder.vrcode ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    private var visibilityActionMessage: some View {
        Group {
            if !viewModel.vitalDBVisibilityActionMessage.isEmpty {
                HStack(spacing: 8) {
                    Text(viewModel.vitalDBVisibilityActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let recentlyHiddenVrcode {
                        Button("Undo") {
                            Task {
                                if await viewModel.unhideVitalDBRecorder(vrcode: recentlyHiddenVrcode) {
                                    selectedVrcode = recentlyHiddenVrcode
                                    self.recentlyHiddenVrcode = nil
                                }
                            }
                        }
                        .disabled(viewModel.isRunningVitalDBVisibilityAction)
                    }
                }
            }
        }
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }

    private func selectedRecorderSummary(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                recorderDetailIdentity(recorder)
                Spacer()
                recorderListVisibilityAction(recorder)
            }
            VStack(alignment: .leading, spacing: 10) {
                recorderDetailIdentity(recorder)
                recorderListVisibilityAction(recorder)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recorderDetailIdentity(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(statusColor(recorder.status))
                .frame(width: 9, height: 9)
            Text(recorder.vrcode)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(statusLabel(recorder.status))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(recorder.status))
            RuntimeRecorderSourceBadge(version: recorder.version)
            if recorder.visibility == .hidden {
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

    @ViewBuilder
    private func recorderListVisibilityAction(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        if recorder.visibility == .hidden {
            Button("Show in list") {
                Task {
                    recentlyHiddenVrcode = nil
                    _ = await viewModel.unhideVitalDBRecorder(vrcode: recorder.vrcode)
                }
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
            .help("Include this recorder in the default recorder list.")
        } else {
            Button("Hide from list") {
                Task {
                    recentlyHiddenVrcode = nil
                    if await viewModel.hideVitalDBRecorder(vrcode: recorder.vrcode) {
                        selectedVrcode = nil
                        recentlyHiddenVrcode = recorder.vrcode
                    }
                }
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
            .help("Removes this recorder from the default list. Recorder data is not deleted.")
        }
    }

    private func recorderNetworkAccess(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Network access")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow("Connection IP", reportedText(recorder.lastIP, missing: "IP not reported"))
                detailRow("IP verification", recorderIPVerificationDetailText(recorder.redisIPSync))
                detailRow("Active IP", reportedText(recorder.redisIPSync?.selectedIp, missing: "Active IP not reported"))
                detailRow("Last checked", recorderIPVerificationCheckedAtText(recorder.redisIPSync))
                detailRow("Last issue", reportedText(recorder.redisIPSync?.lastFailure, missing: "-"))
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recorderVitalFiles(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Vital files")
            if let history = viewModel.recorderVitalFileHistories[recorder.vrcode] {
                if history.files.isEmpty {
                    Text(recorderVitalFilesEmptyText(history))
                        .foregroundStyle(history.state == .readFailed ? .red : .secondary)
                } else {
                    ForEach(history.files) { file in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(file.filename)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(recorderVitalFileOriginText(file.origin))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .windowBackgroundColor))
                                    .clipShape(Capsule())
                                Text(file.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(file.status == .failed ? .red : .secondary)
                            }
                            Text(
                                "\(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))"
                                + " · received \(viewModel.presentationFormatter.systemTimeText(file.receivedAt))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let bedName = file.bedName {
                                Text("Bed \(bedName) · attribution \(file.attribution.state.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let failure = file.failure {
                                Text("\(failure.stage) / \(failure.code): \(failure.message)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("Loading Vital files...")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: recorder.vrcode) {
            await viewModel.refreshVitalRecorderVitalFiles(vrcode: recorder.vrcode)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recorderVitalFilesEmptyText(
        _ history: RuntimeVitalRecorderVitalFileHistory
    ) -> String {
        if let readError = history.readError {
            return "Vital file history read issue: \(readError)"
        }
        return "No tracked Vital files are attributed to this VRecorder."
    }

    private func recorderVitalFileOriginText(
        _ origin: RuntimeVitalRecorderVitalFileOrigin
    ) -> String {
        switch origin {
        case .nativeRecorderUpload:
            return "Recorder upload"
        case .coldPathRecovery:
            return "Cold-path recovery"
        }
    }

    private func recorderActivity(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        let activityQuery = recorderActivityWindowQuery(for: recorder)
        let activityWindow = viewModel.recorderActivityWindow(query: activityQuery)
        let activityDisplay = activityChartDataBuilder.display(from: activityWindow)
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    detailSectionTitle("Activity")
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
                    detailSectionTitle("Activity")
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
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], alignment: .leading, spacing: 8) {
                        activityMetric("Packets", activityDisplay.latestBucket.map { "\($0.messageCount)" } ?? "-")
                        activityMetric("Total packets", activityDisplay.totalPackets.map(String.init) ?? "-")
                        activityMetric("Data rate", activityDisplay.latestBucketBytesPerSecond.map(formatBytesPerSecond) ?? "-")
                    }
                }
                }
            }
        }
        .task(id: recorderActivityWindowTaskID(activityQuery)) {
            await viewModel.pollVitalRecorderActivityWindow(query: activityQuery)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    activityPeriod = .last8Hours
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
        VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Overview")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow(AppConstants.Labels.recorderSource, displayPolicy.recorderSourceText(recorder.version))
                detailRow(AppConstants.Labels.recorderVersion, reportedText(recorder.version, missing: "Version not reported"))
                detailRow(AppConstants.Labels.bed, reportedText(recorder.bedName ?? recorder.bedID, missing: "Bed not reported"))
                detailRow("Bed ID", reportedText(linkedBed(for: recorder)?.bedID ?? recorder.bedID, missing: "Bed ID not reported"))
                detailRow(AppConstants.Labels.patient, patientText(recorder.patientConnected))
                detailRow("First seen", viewModel.presentationFormatter.systemTimeText(recorder.firstSeenAt))
                detailRow(AppConstants.Labels.recorderLastSeen, viewModel.presentationFormatter.systemTimeText(recorder.lastSeenAt))
                detailRow("Latest anomaly", recorderAnomalyDetailText(recorder))
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recorderObservability(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Health report")
            if let detail = viewModel.recorderObservabilityDetails[recorder.vrcode] {
                recorderObservabilityDetail(detail, recorder: recorder)
            } else {
                Text("Loading health detail...")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: recorder.vrcode) {
            async let detail: Void = viewModel.refreshRecorderObservabilityDetail(vrcode: recorder.vrcode)
            async let incidents: Void = viewModel.refreshRecorderObservabilityIncidents(
                query: recorderObservabilityIncidentQuery(vrcode: recorder.vrcode)
            )
            _ = await (detail, incidents)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recorderObservabilityDetail(
        _ detail: RuntimeRecorderObservabilityDetail,
        recorder: RuntimeVitalRecorderRecord
    ) -> some View {
        if detail.vrcode != recorder.vrcode {
            Text("Health detail identity does not match the selected Recorder.")
                .foregroundStyle(.red)
        } else if detail.state == .unavailable {
            Text("Health detail read failed: \(detail.readError ?? "No failure detail was provided.")")
                .foregroundStyle(.red)
        } else {
            if recorderObservabilitySummaryMismatch(detail, recorder: recorder) {
                Text("Recorder list and health detail report different support or report states.")
                    .foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow("Support", recorderObservabilityDetailSupportText(detail))
                detailRow("Report", recorderObservabilityDetailReportText(detail))
                detailRow(
                    "Last report",
                    viewModel.presentationFormatter.systemTimeText(detail.report.receivedAt)
                )
                detailRow(
                    "Operational health",
                    recorderOperationalHealthText(detail.operationalHealth)
                )
                detailRow("Evidence health", recorderObservabilityEvidenceHealthText(detail.evidenceHealth))
                detailRow("Incident assessment", recorderObservabilityIncidentStateText(detail.incidentState))
                detailRow(
                    "Temperature",
                    recorderObservabilityReadingText(
                        detail.readings.temperatureCelsius,
                        suffix: " °C"
                    )
                )
                detailRow(
                    "Memory available",
                    recorderObservabilityByteReadingText(detail.readings.memoryAvailableBytes)
                )
                detailRow(
                    "Memory total",
                    recorderObservabilityByteReadingText(detail.readings.memoryTotalBytes)
                )
                detailRow(
                    "Root storage used",
                    recorderObservabilityReadingText(
                        detail.readings.rootUsedPercent,
                        suffix: "%"
                    )
                )
                detailRow(
                    "Data storage used",
                    recorderObservabilityReadingText(
                        detail.readings.dataUsedPercent,
                        suffix: "%"
                    )
                )
                detailRow(
                    "Recorder service",
                    recorderObservabilityReadingText(detail.readings.recorderActiveState)
                )
                detailRow(
                    "Publisher",
                    recorderObservabilityReadingText(detail.readings.publisherActiveState)
                )
                detailRow(
                    "Publisher buffer",
                    recorderObservabilityByteReadingText(detail.readings.publisherBufferBytes)
                        + " / "
                        + recorderObservabilityByteReadingText(
                            detail.readings.publisherBufferLimitBytes
                        )
                )
                detailRow("Profile", detail.profile.state.rawValue)
                detailRow("Boot", recorderObservabilityBootText(detail))
                detailRow("Read issues", String(detail.report.readIssueCount))
            }
            recorderCurrentIncidentState(detail.incidentState)
            if !detail.operationalHealth.issues.isEmpty {
                Text("Latest reported issues")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 4)
                ForEach(detail.operationalHealth.issues, id: \.code) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(issue.detail)
                            .font(.caption)
                    }
                    .foregroundStyle(
                        issue.severity == .critical ? Color.red : Color.orange
                    )
                }
                if detail.report.state != "current" {
                    Text(
                        "These issues came from the latest report; "
                            + "current device state is unknown."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if !detail.readIssues.isEmpty {
                Text("Telemetry read issues")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 4)
            }
            ForEach(Array(detail.readIssues.enumerated()), id: \.offset) { _, issue in
                Text("\(issue.field): \(issue.state) — \(issue.detail)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !detail.readings.networkInterfaces.isEmpty {
                Text("Network interfaces")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(detail.readings.networkInterfaces, id: \.name) { networkInterface in
                    Text(recorderObservabilityNetworkText(networkInterface))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            recorderIncidentHistory(vrcode: recorder.vrcode)
        }
    }

    @ViewBuilder
    private func recorderCurrentIncidentState(
        _ incidentState: RuntimeRecorderObservabilityIncidentState
    ) -> some View {
        switch incidentState.state {
        case "notReported":
            Text("Current incident assessment has not been reported by this Recorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "invalid":
            Text("Current incident assessment is invalid.")
                .font(.caption)
                .foregroundStyle(.red)
        case "reported":
            if incidentState.bootLoopState == "warning" || incidentState.bootLoopState == "critical" {
                Text("Current boot-loop assessment: \(incidentState.bootLoopState ?? "unknown").")
                    .font(.caption)
                    .foregroundStyle(incidentState.bootLoopState == "critical" ? Color.red : Color.orange)
            }
            if incidentState.repeatedUndervoltageState == "warning"
                || incidentState.repeatedUndervoltageState == "critical" {
                Text("Current repeated-undervoltage assessment: \(incidentState.repeatedUndervoltageState ?? "unknown").")
                    .font(.caption)
                    .foregroundStyle(incidentState.repeatedUndervoltageState == "critical" ? Color.red : Color.orange)
            }
        default:
            Text("Current incident assessment state: \(incidentState.state).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func recorderIncidentHistory(vrcode: String) -> some View {
        let query = recorderObservabilityIncidentQuery(vrcode: vrcode)
        if let page = viewModel.recorderObservabilityIncidentPage(query: query) {
            Text("Recent reported incidents")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 4)
            if page.state == .unavailable {
                Text("Incident history is unavailable: \(page.readError ?? "No failure detail was provided.")")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if page.incidents.isEmpty {
                Text("No reported incident records in the last 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(page.incidents, id: \.incidentId) { incident in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(incident.code) — \(incident.severity)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(incident.summary)
                            .font(.caption)
                        Text("Reported \(viewModel.presentationFormatter.systemTimeText(incident.receivedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(incident.severity == "critical" ? Color.red : Color.orange)
                }
            }
        }
    }

    private func recorderObservabilityIncidentQuery(
        vrcode: String,
        now: Date = Date()
    ) -> RuntimeRecorderObservabilityIncidentQuery {
        let formatter = ISO8601DateFormatter()
        let until = formatter.string(from: now)
        let from = formatter.string(
            from: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        )
        return RuntimeRecorderObservabilityIncidentQuery(
            vrcode: vrcode,
            from: from,
            until: until,
            type: nil,
            cursor: nil,
            limit: 20
        )
    }

    private func recorderObservabilitySummaryMismatch(
        _ detail: RuntimeRecorderObservabilityDetail,
        recorder: RuntimeVitalRecorderRecord
    ) -> Bool {
        guard let summary = recorder.observability else {
            return false
        }
        return summary.supportState.rawValue != detail.support.state
            || summary.reportState.rawValue != detail.report.state
            || (
                summary.operationalHealthState != nil
                    && summary.operationalHealthState != detail.operationalHealth.state
            )
    }

    private func recorderObservabilityDetailSupportText(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> String {
        switch detail.support.state {
        case "supported":
            return "Supported"
        case "unsupported":
            return "Not available on this version"
        default:
            return "Support unknown"
        }
    }

    private func recorderObservabilityDetailReportText(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> String {
        if detail.support.state == "unsupported" {
            return "Not applicable"
        }
        switch detail.report.state {
        case "awaitingFirstReport":
            return "Waiting for first report"
        case "current":
            return "Current"
        case "stale":
            return "Stale"
        case "missing":
            return "Missing"
        case "readFailed":
            return "Unavailable"
        default:
            return "Not evaluated"
        }
    }

    private func recorderObservabilityReadingText(
        _ reading: RuntimeRecorderObservabilityReading,
        suffix: String = ""
    ) -> String {
        guard reading.state == .ok else {
            return reading.state.rawValue
                + (reading.detail.map { " — \($0)" } ?? "")
        }
        guard let value = reading.value else {
            return "invalid — scalar value expected"
        }
        switch value {
        case .bool(let value):
            return "\(value)\(suffix)"
        case .int(let value):
            return "\(value)\(suffix)"
        case .double(let value):
            return "\(value)\(suffix)"
        case .string(let value):
            return "\(value)\(suffix)"
        case .null, .array, .object:
            return "invalid — scalar value expected"
        }
    }

    private func recorderObservabilityByteReadingText(
        _ reading: RuntimeRecorderObservabilityReading
    ) -> String {
        guard reading.state == .ok, let value = reading.value else {
            return recorderObservabilityReadingText(reading)
        }
        let bytes: Int64?
        switch value {
        case .int(let value):
            bytes = Int64(value)
        case .double(let value) where value.isFinite:
            bytes = Int64(value)
        default:
            bytes = nil
        }
        guard let bytes, bytes >= 0 else {
            return "invalid — byte value expected"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func recorderObservabilityNetworkText(
        _ networkInterface: RuntimeRecorderObservabilityNetworkInterface
    ) -> String {
        let state = recorderObservabilityReadingText(networkInterface.operState)
        let carrier = recorderObservabilityReadingText(networkInterface.carrier)
        let rxErrors = recorderObservabilityReadingText(networkInterface.rxErrors)
        let txErrors = recorderObservabilityReadingText(networkInterface.txErrors)
        return "\(networkInterface.name): \(state), carrier \(carrier), "
            + "RX errors \(rxErrors), TX errors \(txErrors)"
    }

    private func recorderObservabilityBootText(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> String {
        switch detail.boot.state {
        case "started":
            return "Started "
                + viewModel.presentationFormatter.systemTimeText(detail.boot.startedAt)
        case "shutdownClean":
            return "Clean shutdown "
                + viewModel.presentationFormatter.systemTimeText(
                    detail.boot.cleanShutdownAt
                )
        default:
            return detail.boot.orderingState == "nonOrderable"
                ? "Reported, but order cannot be established across boot evidence"
                : "Not reported"
        }
    }

    private func recorderObservabilityEvidenceHealthText(
        _ evidenceHealth: RuntimeRecorderObservabilityEvidenceHealth
    ) -> String {
        guard evidenceHealth.state != "notReported" else {
            return "Not reported"
        }
        return evidenceHealth.state + (evidenceHealth.detail.map { " — \($0)" } ?? "")
    }

    private func recorderObservabilityIncidentStateText(
        _ incidentState: RuntimeRecorderObservabilityIncidentState
    ) -> String {
        guard incidentState.state == "reported" else {
            return incidentState.state
        }
        let states = [incidentState.bootLoopState, incidentState.repeatedUndervoltageState]
            .compactMap { $0 }
            .filter { $0 != "none" }
        return states.isEmpty ? "No active reported assessment" : states.joined(separator: ", ")
    }

    private func recorderObservabilitySupportText(
        _ observability: RuntimeRecorderObservability?
    ) -> String {
        switch observability?.supportState {
        case .supported:
            return "Supported"
        case .unsupported:
            return "Not available on this version"
        case .unknown, nil:
            return "Support unknown"
        }
    }

    private func recorderObservabilityReportText(
        _ observability: RuntimeRecorderObservability?
    ) -> String {
        if observability?.supportState == .unsupported {
            return "Not applicable"
        }
        switch observability?.reportState {
        case .awaitingFirstReport:
            return "Waiting for first report"
        case .current:
            return "Current"
        case .stale:
            return "Stale"
        case .missing:
            return "Missing"
        case .readFailed:
            return "Unavailable"
        case .notEvaluated, nil:
            return "Not evaluated"
        }
    }

    private func recorderOperationalHealthSummary(
        _ observability: RuntimeRecorderObservability?
    ) -> String {
        let report = recorderObservabilityReportText(observability)
        let count = observability?.operationalIssueCount ?? 0
        let health: String
        switch observability?.operationalHealthState {
        case .healthy:
            health = "Healthy"
        case .warning:
            health = "Warning (\(count))"
        case .critical:
            health = "Critical (\(count))"
        case .unknown, nil:
            health = "Unknown"
        }
        return "\(health) · report \(report)"
    }

    private func recorderOperationalHealthText(
        _ health: RuntimeRecorderOperationalHealth
    ) -> String {
        switch health.state {
        case .healthy:
            return "Healthy"
        case .warning:
            return "Warning — \(health.issueCount) reported issue(s)"
        case .critical:
            return "Critical — \(health.issueCount) reported issue(s)"
        case .unknown:
            return health.issueCount > 0
                ? "Unknown — \(health.issueCount) issue(s) in the latest report"
                : "Unknown"
        }
    }

    private func recorderRelationshipHistory(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        let history = viewModel.relationshipPresentationHistory(vrcode: recorder.vrcode)
        let assignments = history.assignments
        let events = history.events

        return VStack(alignment: .leading, spacing: 10) {
            detailSectionTitle("Relationship history")
            relationshipReadIssue
            if assignments.isEmpty, events.isEmpty, viewModel.vitalRelationships.state == .loaded {
                Text("No recorder relationship history has been observed.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if viewModel.vitalRelationships.state != .readFailed {
                if !assignments.isEmpty {
                    relationshipSubsection("Assignments")
                    ForEach(assignments) { assignment in
                        relationshipRow(
                            title: assignment.bedName ?? assignment.bedID,
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

    private func recorderDataManagement(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailSectionTitle("Data management")
            Text("Deleting removes this hidden recorder from retained recorder history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete hidden recorder", role: .destructive) {
                recorderVrcodePendingDeletion = recorder.vrcode
            }
            .disabled(viewModel.isRunningVitalDBVisibilityAction)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    private var recorderDeletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { recorderVrcodePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    recorderVrcodePendingDeletion = nil
                }
            }
        )
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
        .font(.title3)
    }

    private func tableHeader(_ text: String, minWidth: CGFloat) -> some View {
        Text(text)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(minWidth: minWidth, alignment: .leading)
    }

    private func tableValue(_ text: String, minWidth: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.title3)
            .fontWeight(weight)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(minWidth: minWidth, alignment: .leading)
    }

    private func tableIPValue(_ recorder: RuntimeVitalRecorderRecord, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reportedText(recorder.lastIP, missing: "IP not reported"))
                .font(.title3)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(recorderIPVerificationSummaryText(recorder.redisIPSync))
                .font(.body)
                .foregroundStyle(recorderIPVerificationColor(recorder.redisIPSync))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tableRecorderIdentity(
        _ recorder: RuntimeVitalRecorderRecord,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            Text(recorder.vrcode)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if recorder.visibility == .hidden {
                Text("Hidden")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
    }

    private func recorderStatusValue(
        _ status: RuntimeVitalRecorderStatus,
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

    private func recorderIPVerificationSummaryText(_ sync: RuntimeRecorderRedisIPSyncObservation?) -> String {
        guard let status = sync?.status else {
            return "IP status not reported"
        }
        switch status {
        case .verified:
            return "IP verified"
        case .corrected:
            return "IP updated"
        case .correcting:
            return "Updating IP"
        case .mismatch:
            return "IP mismatch"
        case .writeFailed:
            return "IP update failed"
        case .verifyFailed:
            return "IP check failed"
        case .pending, .written:
            return "IP check pending"
        case .disabled:
            return "IP tracking disabled"
        case .unknown:
            return "IP status unknown"
        case .unavailable:
            return "IP status unavailable"
        }
    }

    private func recorderIPVerificationDetailText(_ sync: RuntimeRecorderRedisIPSyncObservation?) -> String {
        guard let sync else {
            return "Not reported"
        }
        let base = recorderIPVerificationSummaryText(sync)
        if let lastVerifiedAt = sync.lastVerifiedAt {
            return "\(base) at \(viewModel.presentationFormatter.systemTimeText(lastVerifiedAt))"
        }
        if let lastWriteAt = sync.lastWriteAt {
            return "\(base) at \(viewModel.presentationFormatter.systemTimeText(lastWriteAt))"
        }
        return base
    }

    private func recorderIPVerificationCheckedAtText(_ sync: RuntimeRecorderRedisIPSyncObservation?) -> String {
        viewModel.presentationFormatter.systemTimeText(sync?.lastVerifiedAt ?? sync?.lastWriteAt)
    }

    private func recorderIPVerificationColor(_ sync: RuntimeRecorderRedisIPSyncObservation?) -> Color {
        switch sync?.status {
        case .verified, .corrected:
            return .green
        case .correcting, .pending, .written:
            return .orange
        case .mismatch, .writeFailed, .verifyFailed:
            return .red
        case .disabled, .unknown, .unavailable, nil:
            return .secondary
        }
    }

    private func linkedBed(for recorder: RuntimeVitalRecorderRecord) -> RuntimeVitalBedRecord? {
        if let bedID = recorder.bedID,
           let bed = viewModel.vitalBeds.beds.first(where: { $0.bedID == bedID }) {
            return bed
        }
        return viewModel.vitalBeds.beds.first { $0.vrcode == recorder.vrcode }
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
