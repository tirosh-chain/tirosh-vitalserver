import SwiftUI

struct RuntimeLogPanel: View {
    @ObservedObject var controller: RuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppConstants.Labels.log)
                    .font(.headline)
                Spacer()
                Picker(AppConstants.Labels.logSource, selection: $controller.selectedLogSource) {
                    ForEach(controller.availableLogSources()) { source in
                        Text(source.title).tag(source.id)
                    }
                }
                .frame(width: 210)
                .onChange(of: controller.selectedLogSource) { _ in
                    controller.refreshLogs()
                }
                Picker(AppConstants.Labels.logLines, selection: $controller.logLineLimit) {
                    ForEach(controller.availableLogLineLimits(), id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .frame(width: 150)
                .onChange(of: controller.logLineLimit) { _ in
                    controller.refreshLogs()
                }
                Toggle(AppConstants.Labels.logStreaming, isOn: $controller.logStreaming)
                    .toggleStyle(.checkbox)
                    .onChange(of: controller.logStreaming) { isLive in
                        if isLive {
                            controller.refreshLogs()
                        }
                    }
                Text(controller.logStreaming ? AppConstants.Labels.logLive : AppConstants.Labels.logPaused)
                    .font(.caption)
                    .foregroundStyle(controller.logStreaming ? .green : .secondary)
                Button(AppConstants.Actions.openLogs) {
                    controller.openLogs()
                }
                Button(AppConstants.Actions.exportLogs) {
                    Task { await controller.exportLogs() }
                }
                .disabled(controller.isBusy || !controller.capabilities.canExportLogs)
            }
            ScrollView {
                Text(controller.logText)
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
