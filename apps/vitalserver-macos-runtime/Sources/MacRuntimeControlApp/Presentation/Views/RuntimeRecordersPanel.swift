import RuntimeControl
import SwiftUI

struct RuntimeRecordersPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var searchText = ""
    @State private var selectedVrcode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    recorderList
                        .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)
                    recorderDetails
                        .frame(minWidth: 380, maxWidth: 560, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 14) {
                    recorderList
                    recorderDetails
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(AppConstants.Labels.sectionRecorders)
                    .font(.headline)
                Spacer()
                recorderSearchField
                refreshButton
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppConstants.Labels.sectionRecorders)
                    .font(.headline)
                HStack {
                    recorderSearchField
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
            bedObservations
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
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalRecorders.beds.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(viewModel.vitalRecorders.recorders.reduce(0) { $0 + $1.currentAnomalyCount })")
            }
            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
                summaryMetric(AppConstants.Labels.knownBeds, "\(viewModel.vitalRecorders.beds.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(viewModel.vitalRecorders.recorders.reduce(0) { $0 + $1.currentAnomalyCount })")
            }
        }
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 12)]
    }

    private var filteredRecorders: [RuntimeVitalRecorderRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return viewModel.vitalRecorders.recorders
        }
        return viewModel.vitalRecorders.recorders.filter { recorder in
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

    private var selectedRecorder: RuntimeVitalRecorderRecord? {
        if let selectedVrcode,
           let recorder = viewModel.vitalRecorders.recorders.first(where: { $0.vrcode == selectedVrcode }) {
            return recorder
        }
        return filteredRecorders.first
    }

    private var bedObservations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppConstants.Labels.knownBeds)
                .font(.subheadline)
                .fontWeight(.semibold)
            if viewModel.vitalRecorders.beds.isEmpty {
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
                        ForEach(viewModel.vitalRecorders.beds) { bed in
                            Divider()
                            bedRow(bed)
                        }
                    }
                    .frame(minWidth: 650, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
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

    private var bedHeaderRow: some View {
        HStack(spacing: 12) {
            tableHeader("Bed ID", minWidth: 160)
            tableHeader("Name", minWidth: 120)
            tableHeader("VRecorder", minWidth: 120)
            tableHeader(AppConstants.Labels.recorderStatus, minWidth: 80)
            tableHeader(AppConstants.Labels.recorderLastSeen, minWidth: 170)
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
                tableValue(recorder.currentAnomalyCount == 0 ? "-" : "\(recorder.currentAnomalyCount)", minWidth: 70)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(selectedRecorder?.vrcode == recorder.vrcode ? Color.accentColor.opacity(0.10) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func bedRow(_ bed: RuntimeVitalBedRecord) -> some View {
        HStack(spacing: 12) {
            tableValue(bed.bedID, minWidth: 160, weight: .semibold)
            tableValue(bed.name ?? AppConstants.StatusText.unknown, minWidth: 120)
            tableValue(bed.vrcode ?? AppConstants.StatusText.unknown, minWidth: 120)
            Text(bed.status.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor(bed.status))
                .frame(minWidth: 80, alignment: .leading)
            tableValue(
                viewModel.presentationFormatter.systemTimeText(bed.lastSeenAt),
                minWidth: 170
            )
        }
        .padding(10)
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let latest {
                    Text("Last sample \(viewModel.presentationFormatter.systemTimeText(latest.observedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if recorder.activityTimeline.isEmpty {
                Text("No recent data activity has been observed for this VRecorder.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                RecorderActivityChart(points: recorder.activityTimeline)
                    .frame(height: 150)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        activityMetric("Data rate", latest.map { formatBytesPerSecond($0.bytesPerSecond) } ?? "-")
                        activityMetric("Messages", latest.map { "\($0.messageCount)" } ?? "-")
                        activityMetric("Rooms", latest.map { "\($0.roomCount)" } ?? "-")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], alignment: .leading, spacing: 8) {
                        activityMetric("Data rate", latest.map { formatBytesPerSecond($0.bytesPerSecond) } ?? "-")
                        activityMetric("Messages", latest.map { "\($0.messageCount)" } ?? "-")
                        activityMetric("Rooms", latest.map { "\($0.roomCount)" } ?? "-")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        viewModel.vitalRecorders.recorders.filter { $0.status == status }.count
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
}

private struct RecorderActivityChart: View {
    let points: [RuntimeVitalRecorderActivityPoint]

    var body: some View {
        GeometryReader { proxy in
            let plottedPoints = chartPoints(in: proxy.size)
            ZStack {
                chartGrid
                activityPath(points: plottedPoints)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(plottedPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topLeading) {
            Text("Data rate")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var chartGrid: some View {
        GeometryReader { proxy in
            Path { path in
                let height = proxy.size.height
                let width = proxy.size.width
                for fraction in [0.25, 0.5, 0.75] {
                    let y = height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private func activityPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else {
                return
            }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let inset = EdgeInsets(top: 28, leading: 12, bottom: 16, trailing: 12)
        let width = max(size.width - inset.leading - inset.trailing, 1)
        let height = max(size.height - inset.top - inset.bottom, 1)
        let maxValue = max(points.map(\.bytesPerSecond).max() ?? 0, 1)

        return points.enumerated().map { index, point in
            let x: CGFloat
            if points.count <= 1 {
                x = inset.leading + width / 2
            } else {
                x = inset.leading + width * CGFloat(index) / CGFloat(points.count - 1)
            }
            let normalized = min(max(point.bytesPerSecond / maxValue, 0), 1)
            let y = inset.top + height - height * CGFloat(normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
