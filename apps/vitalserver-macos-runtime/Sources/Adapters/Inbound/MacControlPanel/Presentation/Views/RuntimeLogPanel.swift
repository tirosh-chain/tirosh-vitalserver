import Foundation
import SwiftUI
import Errors

struct RuntimeLogPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.logText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear
                            .frame(height: 1)
                            .id(logBottomID)
                    }
                }
                .onAppear {
                    scrollToLatestLog(proxy, animated: false)
                }
                .onChange(of: viewModel.logText) {
                    if viewModel.logStreaming {
                        scrollToLatestLog(proxy)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var logBottomID: String {
        "runtime-log-bottom"
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title
                Spacer()
                sourceControl
                linesControl
                liveControl
                logActions
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    title
                    Spacer()
                    logActions
                }
                HStack(spacing: 12) {
                    sourceControl
                    linesControl
                    liveControl
                    Spacer()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                sourceControl
                HStack(spacing: 12) {
                    linesControl
                    liveControl
                    Spacer()
                }
                logActions
            }
        }
    }

    private var title: some View {
        Text(AppConstants.Labels.log)
            .font(.headline)
    }

    private var sourceControl: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.logSource)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: $viewModel.selectedLogSource) {
                ForEach(viewModel.availableLogSources()) { source in
                    Text(source.title).tag(source.id)
                }
            }
            .frame(width: 210)
            .labelsHidden()
            .onChange(of: viewModel.selectedLogSource) {
                Task { await viewModel.refreshLogs() }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var linesControl: some View {
        HStack(spacing: 8) {
            Text(AppConstants.Labels.logLines)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: $viewModel.logLineLimit) {
                ForEach(viewModel.availableLogLineLimits(), id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
            .frame(width: 120)
            .labelsHidden()
            .onChange(of: viewModel.logLineLimit) {
                Task { await viewModel.refreshLogs() }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var liveControl: some View {
        HStack(spacing: 6) {
            Toggle(AppConstants.Labels.logStreaming, isOn: $viewModel.logStreaming)
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: viewModel.logStreaming) { _, isLive in
                    if isLive {
                        Task { await viewModel.refreshLogs() }
                    }
                }
            Text(viewModel.logStreaming ? AppConstants.Labels.logLive : AppConstants.Labels.logPaused)
                .font(.caption)
                .foregroundStyle(viewModel.logStreaming ? .green : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var logActions: some View {
        HStack(spacing: 8) {
            Button(AppConstants.Actions.openLogs) {
                viewModel.openLogs()
            }
            Button(AppConstants.Actions.exportLogs) {
                Task { await viewModel.exportLogs() }
            }
            .disabled(viewModel.isBusy || !viewModel.capabilities.canExportLogs)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func scrollToLatestLog(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(logBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(logBottomID, anchor: .bottom)
            }
        }
    }
}
