import Contracts
import RuntimeControl
import SwiftUI

struct RuntimeEventsPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

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
                    ForEach(viewModel.runtimeEvents.events, id: \.id) { event in
                        eventRow(event)
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

    private func eventRow(_ event: RuntimeEventDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(event.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.eventType.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(event.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(statusColor(event.status))
                Spacer()
                Text(event.operation.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(event.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let observation = event.containerObservation?.auditProxyStatus {
                Text("\(AppConstants.Labels.activeRecorderConnections): \(observation.activeRecorderConnections), \(AppConstants.Labels.knownRecorders): \(observation.recorders.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusColor(_ status: RuntimeStatusLevel) -> Color {
        switch status {
        case .healthy:
            return .green
        case .critical:
            return .red
        case .degraded, .recovering:
            return .orange
        default:
            return .secondary
        }
    }
}
