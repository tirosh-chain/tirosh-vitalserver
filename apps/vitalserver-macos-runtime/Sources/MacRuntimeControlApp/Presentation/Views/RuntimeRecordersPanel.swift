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
                        .frame(minWidth: 460, maxWidth: .infinity, alignment: .topLeading)
                    recorderDetails
                        .frame(minWidth: 260, maxWidth: 360, alignment: .topLeading)
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
        }
    }

    private var recorderDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.recorderDetails)
                .font(.headline)
            if let recorder = selectedRecorder {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    detailRow("VRecorder", recorder.vrcode)
                    detailRow(AppConstants.Labels.recorderStatus, recorder.status.rawValue.capitalized)
                    detailRow("IP", recorder.lastIP ?? AppConstants.StatusText.unknown)
                    detailRow(AppConstants.Labels.recorderVersion, recorder.version ?? AppConstants.StatusText.unknown)
                    detailRow(AppConstants.Labels.bed, recorder.bedName ?? recorder.bedID ?? AppConstants.StatusText.unknown)
                    detailRow(AppConstants.Labels.patient, patientText(recorder.patientConnected))
                    detailRow("First seen", recorder.firstSeenAt ?? AppConstants.StatusText.unknown)
                    detailRow(AppConstants.Labels.recorderLastSeen, recorder.lastSeenAt ?? AppConstants.StatusText.unknown)
                    detailRow(AppConstants.Labels.observations, "\(recorder.observationCount)")
                    detailRow(AppConstants.Labels.recorderAnomalies, "\(recorder.currentAnomalyCount)")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(AppConstants.StatusText.noVitalRecorderObservations)
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
            viewModel.refreshVitalRecorders()
        }
    }

    private var summaryMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
                summaryMetric(AppConstants.Labels.onlineRecorders, "\(count(.online))")
                summaryMetric(AppConstants.Labels.staleRecorders, "\(count(.stale))")
                summaryMetric(AppConstants.Labels.recorderAnomalies, "\(viewModel.vitalRecorders.recorders.reduce(0) { $0 + $1.currentAnomalyCount })")
            }
            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                summaryMetric(AppConstants.Labels.knownRecorders, "\(viewModel.vitalRecorders.recorders.count)")
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
                tableValue(recorder.currentAnomalyCount == 0 ? "-" : "\(recorder.currentAnomalyCount)", minWidth: 70)
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

    private func patientText(_ connected: Bool?) -> String {
        guard let connected else {
            return AppConstants.StatusText.unknown
        }
        return connected ? "Connected" : "Not connected"
    }
}
