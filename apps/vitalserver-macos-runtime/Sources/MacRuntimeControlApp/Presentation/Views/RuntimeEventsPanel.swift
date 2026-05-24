import SwiftUI

struct RuntimeEventsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    private let displayPolicy = RuntimeEventDisplayPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppConstants.Labels.sectionEvents)
                    .font(.headline)
                Spacer()
                Button(AppConstants.Actions.refresh) {
                    viewModel.refreshRuntimeEvents()
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(eventItems) { item in
                        eventRow(item)
                    }
                    if viewModel.runtimeEvents.events.isEmpty {
                        Text(AppConstants.StatusText.noRuntimeEvents)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var eventItems: [RuntimeEventDisplayPolicy.EventItem] {
        viewModel.runtimeEvents.events.map(displayPolicy.item)
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
