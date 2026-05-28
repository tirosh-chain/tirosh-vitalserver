import Contracts
import Foundation
import RuntimeControl
import SwiftUI

struct RuntimeRecordersPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedVrcode: String?
    @State private var showingRecorderHistory = false
    @State private var activityBucketInterval = RecorderActivityBucketInterval.oneMinute
    @State private var activityPeriod = RecorderActivityPeriod.lastHour

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
                Toggle("History", isOn: $showingRecorderHistory)
                    .toggleStyle(.switch)
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionRecorders)
                    .font(.headline)
                HStack {
                    recorderSearchField
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
                Text(AppConstants.StatusText.noVitalRecorderObservations)
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
                    .frame(minWidth: 710, alignment: .leading)
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
            }
            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
                summaryMetric("Current", "\(currentRecorders.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric("Assignments", "\(viewModel.vitalRelationships.assignments.count)")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(currentRecorders.reduce(0) { $0 + $1.currentAnomalyCount })")
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
        showingRecorderHistory ? viewModel.vitalRecorders.recorders : currentRecorders
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
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 170)
            tableHeader(AppConstants.Labels.anomaly, minWidth: 70)
        }
        .padding(10)
    }

    private func recorderRow(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        Button {
            selectedVrcode = recorder.vrcode
        } label: {
            HStack(spacing: 12) {
                tableValue(recorder.vrcode, minWidth: 120, weight: .semibold)
                Text(recorder.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(recorder.status))
                    .frame(minWidth: 80, alignment: .leading)
                tableValue(recorder.lastIP ?? AppConstants.StatusText.unknown, minWidth: 120)
                tableValue(recorder.bedName ?? recorder.bedID ?? AppConstants.StatusText.unknown, minWidth: 120)
                tableValue(recorder.lastSeenAt ?? AppConstants.StatusText.unknown, minWidth: 170)
                tableValue(recorderAnomalyText(recorder), minWidth: 70)
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
            Text(recorder.status.rawValue.capitalized)
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
        let latest = recorder.activityTimeline.last
        let buckets = displayActivityBuckets(
            activityBuckets(from: recorder.activityTimeline, interval: activityBucketInterval),
            interval: activityBucketInterval,
            period: activityPeriod
        )
        let totalPackets = buckets.reduce(0) { $0 + $1.messageCount }
        let latestBucket = buckets.last(where: { $0.messageCount > 0 }) ?? buckets.last
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text("Activity")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    activityControls
                    if let latest {
                        Text("Last sample \(viewModel.presentationFormatter.systemTimeText(latest.observedAt))")
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
                        activityControls
                        if let latest {
                            Text("Last sample \(viewModel.presentationFormatter.systemTimeText(latest.observedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
            }

            if recorder.activityTimeline.isEmpty {
                Text("No recent data activity has been observed for this VRecorder.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                if buckets.isEmpty {
                    Text("No data activity has been observed in the selected period.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    RecorderActivityChart(
                        buckets: buckets,
                        intervalTitle: activityBucketInterval.title
                    )
                        .frame(height: 190)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            activityMetric("Packets", latestBucket.map { "\($0.messageCount)" } ?? "-")
                            activityMetric("Total packets", "\(totalPackets)")
                            activityMetric("Data rate", latest.map { formatBytesPerSecond($0.bytesPerSecond) } ?? "-")
                            activityMetric("Rooms", latestBucket.map { "\($0.roomCount)" } ?? "-")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], alignment: .leading, spacing: 8) {
                            activityMetric("Packets", latestBucket.map { "\($0.messageCount)" } ?? "-")
                            activityMetric("Total packets", "\(totalPackets)")
                            activityMetric("Data rate", latest.map { formatBytesPerSecond($0.bytesPerSecond) } ?? "-")
                            activityMetric("Rooms", latestBucket.map { "\($0.roomCount)" } ?? "-")
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            Picker("", selection: $activityPeriod) {
                ForEach(RecorderActivityPeriod.allCases) { period in
                    Text(period.title).tag(period)
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
            Picker("", selection: $activityBucketInterval) {
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

    private func recorderMetadata(_ recorder: RuntimeVitalRecorderRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
            detailRow("IP", recorder.lastIP ?? AppConstants.StatusText.unknown)
            detailRow(AppConstants.Labels.recorderVersion, recorder.version ?? AppConstants.StatusText.unknown)
            detailRow(AppConstants.Labels.bed, recorder.bedName ?? recorder.bedID ?? AppConstants.StatusText.unknown)
            detailRow("Bed ID", linkedBed(for: recorder)?.bedID ?? recorder.bedID ?? AppConstants.StatusText.unknown)
            detailRow(AppConstants.Labels.patient, patientText(recorder.patientConnected))
            detailRow("First seen", viewModel.presentationFormatter.systemTimeText(recorder.firstSeenAt))
            detailRow(AppConstants.Labels.recorderLastSeen, viewModel.presentationFormatter.systemTimeText(recorder.lastSeenAt))
            detailRow(AppConstants.Labels.observations, "\(recorder.observationCount)")
            detailRow(AppConstants.Labels.recorderAnomalies, "\(recorder.currentAnomalyCount)")
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
            if assignments.isEmpty, events.isEmpty {
                Text("No recorder relationship history has been observed.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
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
        if !recorder.presentInLatestObservation {
            return "History"
        }
        return recorder.currentAnomalyCount == 0 ? "-" : "\(recorder.currentAnomalyCount)"
    }

    private func statusColor(_ status: RuntimeVitalRecorderStatus) -> Color {
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

    private func linkedBed(for recorder: RuntimeVitalRecorderRecord) -> RuntimeVitalBedRecord? {
        if let bedID = recorder.bedID,
           let bed = viewModel.vitalRecorders.beds.first(where: { $0.bedID == bedID }) {
            return bed
        }
        return viewModel.vitalRecorders.beds.first { $0.vrcode == recorder.vrcode }
    }

    private func patientText(_ connected: Bool?) -> String {
        guard let connected else {
            return AppConstants.StatusText.unknown
        }
        return connected ? "Connected" : "Not connected"
    }

    private func formatBytesPerSecond(_ value: Double) -> String {
        let boundedValue = max(value, 0)
        if boundedValue < 1, boundedValue > 0 {
            return String(format: "%.2f B/s", boundedValue)
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        return "\(formatter.string(fromByteCount: Int64(boundedValue.rounded())))/s"
    }

    private func activityBuckets(
        from points: [RuntimeVitalRecorderActivityPoint],
        interval: RecorderActivityBucketInterval
    ) -> [RecorderActivityChartBucket] {
        let rawBuckets = points.last?.buckets ?? []
        if rawBuckets.isEmpty {
            return points.map {
                RecorderActivityChartBucket(
                    bucketStartedAt: $0.observedAt,
                    bucketSeconds: interval.seconds,
                    messageCount: $0.messageCount,
                    byteCount: $0.byteCount,
                    roomCount: $0.roomCount
                )
            }
        }

        if interval == .oneMinute {
            return rawBuckets.map(RecorderActivityChartBucket.init)
        }

        var builders: [String: RecorderActivityChartBucketBuilder] = [:]
        for bucket in rawBuckets {
            let startedAt = normalizedBucketStart(
                bucket.bucketStartedAt,
                intervalSeconds: interval.seconds
            )
            var builder = builders[startedAt] ?? RecorderActivityChartBucketBuilder(
                bucketStartedAt: startedAt,
                bucketSeconds: interval.seconds
            )
            builder.add(bucket)
            builders[startedAt] = builder
        }
        return builders.values
            .map(\.bucket)
            .sorted { $0.bucketStartedAt < $1.bucketStartedAt }
    }

    private func displayActivityBuckets(
        _ buckets: [RecorderActivityChartBucket],
        interval: RecorderActivityBucketInterval,
        period: RecorderActivityPeriod
    ) -> [RecorderActivityChartBucket] {
        guard let periodSeconds = period.interval,
              let latest = buckets.compactMap({ RuntimeRecorderActivityDateParser.date(from: $0.bucketStartedAt) }).max() else {
            return buckets
        }
        let threshold = latest.addingTimeInterval(-periodSeconds)
        let filtered = buckets.filter { bucket in
            guard let date = RuntimeRecorderActivityDateParser.date(from: bucket.bucketStartedAt) else {
                return true
            }
            return date >= threshold
        }
        return filledActivityBuckets(
            filtered,
            start: threshold,
            end: latest,
            interval: interval
        )
    }

    private func filledActivityBuckets(
        _ buckets: [RecorderActivityChartBucket],
        start: Date,
        end: Date,
        interval: RecorderActivityBucketInterval
    ) -> [RecorderActivityChartBucket] {
        guard !buckets.isEmpty else {
            return []
        }
        let intervalSeconds = interval.seconds
        let startTimestamp = floor(start.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        let endTimestamp = floor(end.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        var existing: [String: RecorderActivityChartBucket] = [:]
        for bucket in buckets {
            let key = normalizedBucketStart(bucket.bucketStartedAt, intervalSeconds: intervalSeconds)
            let normalizedBucket = RecorderActivityChartBucket(
                bucketStartedAt: key,
                bucketSeconds: intervalSeconds,
                messageCount: bucket.messageCount,
                byteCount: bucket.byteCount,
                roomCount: bucket.roomCount
            )
            existing[key] = existing[key].map { $0.merging(normalizedBucket) } ?? normalizedBucket
        }

        var result: [RecorderActivityChartBucket] = []
        var cursor = startTimestamp
        while cursor <= endTimestamp {
            let key = RuntimeRecorderActivityDateParser.string(from: Date(timeIntervalSince1970: cursor))
            result.append(existing[key] ?? RecorderActivityChartBucket(
                bucketStartedAt: key,
                bucketSeconds: intervalSeconds,
                messageCount: 0,
                byteCount: 0,
                roomCount: 0
            ))
            cursor += Double(intervalSeconds)
        }
        return result
    }

    private func normalizedBucketStart(_ timestamp: String, intervalSeconds: Int) -> String {
        guard let date = RuntimeRecorderActivityDateParser.date(from: timestamp) else {
            return timestamp
        }
        let bucketTimestamp = floor(date.timeIntervalSince1970 / Double(intervalSeconds)) * Double(intervalSeconds)
        return RuntimeRecorderActivityDateParser.string(from: Date(timeIntervalSince1970: bucketTimestamp))
    }
}

private struct RecorderActivityChart: View {
    let buckets: [RecorderActivityChartBucket]
    let intervalTitle: String

    var body: some View {
        GeometryReader { proxy in
            let plotFrame = plotFrame(in: proxy.size)
            let bars = chartBars(in: proxy.size)
            ZStack {
                chartGrid(in: plotFrame)
                chartAxes(in: plotFrame)
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: bar.cornerRadius)
                        .fill(Color.accentColor)
                        .frame(width: bar.rect.width, height: bar.rect.height)
                        .position(x: bar.rect.midX, y: bar.rect.midY)
                }
                ForEach(yAxisLabels(in: plotFrame)) { label in
                    Text(label.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: chartInsets.leading - 10, alignment: .trailing)
                        .position(x: (chartInsets.leading - 10) / 2, y: label.position)
                }
                ForEach(xAxisLabels(in: plotFrame)) { label in
                    Text(label.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: label.width, alignment: label.alignment)
                        .position(x: label.clampedPosition(in: plotFrame), y: plotFrame.maxY + 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topLeading) {
            Text("Packets / \(intervalTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(buckets.reduce(0) { $0 + $1.messageCount }) packets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var chartInsets: EdgeInsets {
        EdgeInsets(top: 32, leading: 54, bottom: 30, trailing: 14)
    }

    private var maxMessageCount: Int {
        max(buckets.map(\.messageCount).max() ?? 0, 1)
    }

    private var yAxisMax: Int {
        niceAxisMax(for: maxMessageCount)
    }

    private func chartGrid(in plotFrame: CGRect) -> some View {
        Path { path in
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let y = plotFrame.maxY - plotFrame.height * fraction
                path.move(to: CGPoint(x: plotFrame.minX, y: y))
                path.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
            }
        }
        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
    }

    private func chartAxes(in plotFrame: CGRect) -> some View {
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: plotFrame.minY))
            path.addLine(to: CGPoint(x: plotFrame.minX, y: plotFrame.maxY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: plotFrame.maxY))
        }
        .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
    }

    private func chartBars(in size: CGSize) -> [RecorderActivityBar] {
        let frame = plotFrame(in: size)
        let width = max(frame.width, 1)
        let height = max(frame.height, 1)
        let maxValue = yAxisMax
        let slotWidth = max(width / CGFloat(max(buckets.count, 1)), 1)
        let barWidth = min(max(slotWidth * 0.68, 1), slotWidth > 4 ? 18 : 2)
        let cornerRadius = min(barWidth / 2, 3)

        return buckets.enumerated().map { index, bucket in
            let normalized = CGFloat(bucket.messageCount) / CGFloat(maxValue)
            let barHeight = max(height * normalized, bucket.messageCount > 0 ? 2 : 0)
            let x = frame.minX + slotWidth * CGFloat(index) + slotWidth / 2
            let y = frame.minY + height - barHeight
            return RecorderActivityBar(
                id: bucket.id,
                rect: CGRect(x: x - barWidth / 2, y: y, width: barWidth, height: barHeight),
                cornerRadius: cornerRadius
            )
        }
    }

    private func plotFrame(in size: CGSize) -> CGRect {
        let width = max(size.width - chartInsets.leading - chartInsets.trailing, 1)
        let height = max(size.height - chartInsets.top - chartInsets.bottom, 1)
        return CGRect(x: chartInsets.leading, y: chartInsets.top, width: width, height: height)
    }

    private func yAxisLabels(in plotFrame: CGRect) -> [RecorderActivityAxisLabel] {
        let maxValue = yAxisMax
        let top = RecorderActivityAxisLabel(id: "y-top", title: "\(maxValue)", position: plotFrame.minY)
        let bottom = RecorderActivityAxisLabel(id: "y-bottom", title: "0", position: plotFrame.maxY)
        guard maxValue > 1 else {
            return [top, bottom]
        }
        let middle = RecorderActivityAxisLabel(
            id: "y-middle",
            title: "\(Int((Double(maxValue) / 2).rounded()))",
            position: plotFrame.midY
        )
        return [top, middle, bottom]
    }

    private func xAxisLabels(in plotFrame: CGRect) -> [RecorderActivityAxisLabel] {
        let datedBuckets = buckets.compactMap { bucket -> (String, Date)? in
            guard let date = RuntimeRecorderActivityDateParser.date(from: bucket.bucketStartedAt) else {
                return nil
            }
            return (bucket.bucketStartedAt, date)
        }
        guard let first = datedBuckets.first,
              let last = datedBuckets.last else {
            return []
        }

        let start = RecorderActivityAxisLabel(
            id: "x-start",
            title: RuntimeRecorderActivityDateParser.axisText(first.1),
            position: plotFrame.minX
        )
        let end = RecorderActivityAxisLabel(
            id: "x-end",
            title: RuntimeRecorderActivityDateParser.axisText(last.1),
            position: plotFrame.maxX
        )
        guard datedBuckets.count > 2 else {
            return plotFrame.width > 220 ? [start, end] : [end]
        }
        let middleIndex = datedBuckets.count / 2
        let middleDate = datedBuckets[middleIndex].1
        let ratio = CGFloat(middleIndex) / CGFloat(max(datedBuckets.count - 1, 1))
        let middle = RecorderActivityAxisLabel(
            id: "x-middle",
            title: RuntimeRecorderActivityDateParser.axisText(middleDate),
            position: plotFrame.minX + plotFrame.width * ratio
        )
        if plotFrame.width < 260 {
            return [end]
        }
        if plotFrame.width < 480 {
            return [start, end]
        }
        return [start, middle, end]
    }

    private func niceAxisMax(for value: Int) -> Int {
        guard value > 0 else {
            return 1
        }
        let magnitude = pow(10.0, floor(log10(Double(value))))
        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            let candidate = Int(multiplier * magnitude)
            if candidate >= value {
                return max(candidate, 1)
            }
        }
        return value
    }
}

private struct RecorderActivityAxisLabel: Identifiable {
    let id: String
    let title: String
    let position: CGFloat
    var width: CGFloat = 74
    var alignment: Alignment = .center

    func clampedPosition(in plotFrame: CGRect) -> CGFloat {
        min(max(position, plotFrame.minX + width / 2), plotFrame.maxX - width / 2)
    }
}

private enum RecorderActivityBucketInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute:
            return "1 min"
        case .fiveMinutes:
            return "5 min"
        }
    }
}

private enum RecorderActivityPeriod: String, CaseIterable, Identifiable {
    case last15Minutes = "last-15-minutes"
    case lastHour = "last-hour"
    case last6Hours = "last-6-hours"
    case last24Hours = "last-24-hours"
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last15Minutes:
            return "Last 15 min"
        case .lastHour:
            return "Last hour"
        case .last6Hours:
            return "Last 6 hours"
        case .last24Hours:
            return "Last 24 hours"
        case .all:
            return "All"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .last15Minutes:
            return 15 * 60
        case .lastHour:
            return 60 * 60
        case .last6Hours:
            return 6 * 60 * 60
        case .last24Hours:
            return 24 * 60 * 60
        case .all:
            return nil
        }
    }
}

private struct RecorderActivityChartBucket: Identifiable {
    var id: String { "\(bucketStartedAt)-\(bucketSeconds)" }
    let bucketStartedAt: String
    let bucketSeconds: Int
    let messageCount: Int
    let byteCount: Int
    let roomCount: Int

    init(_ bucket: VitalDBRecorderActivityBucket) {
        self.init(
            bucketStartedAt: bucket.bucketStartedAt,
            bucketSeconds: bucket.bucketSeconds,
            messageCount: bucket.messageCount,
            byteCount: bucket.byteCount,
            roomCount: bucket.roomCount
        )
    }

    init(
        bucketStartedAt: String,
        bucketSeconds: Int,
        messageCount: Int,
        byteCount: Int,
        roomCount: Int
    ) {
        self.bucketStartedAt = bucketStartedAt
        self.bucketSeconds = bucketSeconds
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.roomCount = roomCount
    }

    func merging(_ other: RecorderActivityChartBucket) -> RecorderActivityChartBucket {
        RecorderActivityChartBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: messageCount + other.messageCount,
            byteCount: byteCount + other.byteCount,
            roomCount: max(roomCount, other.roomCount)
        )
    }
}

private struct RecorderActivityChartBucketBuilder {
    let bucketStartedAt: String
    let bucketSeconds: Int
    var messageCount = 0
    var byteCount = 0
    var roomCount = 0

    mutating func add(_ bucket: VitalDBRecorderActivityBucket) {
        messageCount += bucket.messageCount
        byteCount += bucket.byteCount
        roomCount += bucket.roomCount
    }

    var bucket: RecorderActivityChartBucket {
        RecorderActivityChartBucket(
            bucketStartedAt: bucketStartedAt,
            bucketSeconds: bucketSeconds,
            messageCount: messageCount,
            byteCount: byteCount,
            roomCount: roomCount
        )
    }
}

private struct RecorderActivityBar: Identifiable {
    let id: String
    let rect: CGRect
    let cornerRadius: CGFloat
}

private enum RuntimeRecorderActivityDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    static func axisText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
