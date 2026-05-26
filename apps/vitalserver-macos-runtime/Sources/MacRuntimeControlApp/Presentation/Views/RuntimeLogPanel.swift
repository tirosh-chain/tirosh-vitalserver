import SwiftUI

struct RuntimeLogPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppConstants.Labels.log)
                    .font(.headline)
                Spacer()
                Picker(AppConstants.Labels.logSource, selection: $viewModel.selectedLogSource) {
                    ForEach(viewModel.availableLogSources()) { source in
                        Text(source.title).tag(source.id)
                    }
                }
                .frame(width: 210)
                .onChange(of: viewModel.selectedLogSource) { _ in
                    Task { await viewModel.refreshLogs() }
                }
                Picker(AppConstants.Labels.logLines, selection: $viewModel.logLineLimit) {
                    ForEach(viewModel.availableLogLineLimits(), id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .frame(width: 150)
                .onChange(of: viewModel.logLineLimit) { _ in
                    Task { await viewModel.refreshLogs() }
                }
                Toggle(AppConstants.Labels.logStreaming, isOn: $viewModel.logStreaming)
                    .toggleStyle(.checkbox)
                    .onChange(of: viewModel.logStreaming) { isLive in
                        if isLive {
                            Task { await viewModel.refreshLogs() }
                        }
                    }
                Text(viewModel.logStreaming ? AppConstants.Labels.logLive : AppConstants.Labels.logPaused)
                    .font(.caption)
                    .foregroundStyle(viewModel.logStreaming ? .green : .secondary)
                Button(AppConstants.Actions.openLogs) {
                    viewModel.openLogs()
                }
                Button(AppConstants.Actions.exportLogs) {
                    Task { await viewModel.exportLogs() }
                }
                .disabled(viewModel.isBusy || !viewModel.capabilities.canExportLogs)
            }
            ScrollView {
                Text(viewModel.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
