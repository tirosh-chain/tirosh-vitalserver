import Foundation
import SwiftUI

struct RuntimeLabPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RuntimeLabPanelText.summary)
                        .font(.headline)
                    Text(RuntimeLabPanelText.description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                productLabCard
                browserCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
        .task {
            await viewModel.refreshProductLabScenarios()
        }
    }

    private var productLabCard: some View {
        testCard(RuntimeLabPanelText.productLab) {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    statusRow(AppConstants.Labels.status) {
                        Text(displayName(viewModel.labScenarios.state.rawValue))
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.scenario) {
                        if viewModel.labScenarios.scenarios.isEmpty {
                            Text(AppConstants.Values.empty)
                                .fontWeight(.medium)
                        } else {
                            Picker(AppConstants.Labels.scenario, selection: $viewModel.selectedLabScenarioID) {
                                ForEach(viewModel.labScenarios.scenarios, id: \.scenarioId) { scenario in
                                    Text(scenario.name).tag(scenario.scenarioId)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280)
                        }
                    }
                    statusRow(AppConstants.Labels.sessions) {
                        Text(viewModel.selectedLabSessionID.isEmpty ? AppConstants.Values.empty : viewModel.selectedLabSessionID)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let session = viewModel.labSessionResponse.session {
                        statusRow(AppConstants.Labels.recorders) {
                            Text(String(session.recorderCount))
                                .fontWeight(.medium)
                        }
                        statusRow(AppConstants.Labels.target) {
                            Text(session.targetURL ?? AppConstants.StatusText.notAvailable)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if let readError = viewModel.labScenarios.readError ?? viewModel.labSessionResponse.readError,
                       !readError.isEmpty {
                        statusRow(AppConstants.Labels.lastError) {
                            Text(readError)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !viewModel.labActionMessage.isEmpty {
                        statusRow(AppConstants.Labels.operation) {
                            Text(viewModel.labActionMessage)
                                .fontWeight(.medium)
                                .foregroundStyle(labActionMessageColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("Session name", text: $viewModel.labSessionName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)

                        Stepper(
                            "\(AppConstants.Labels.recorders): \(viewModel.labRecorderCount)",
                            value: $viewModel.labRecorderCount,
                            in: 1...200
                        )
                        .frame(width: 190, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        Button(AppConstants.Actions.refresh) {
                            Task { await viewModel.refreshProductLabScenarios() }
                        }
                        .disabled(viewModel.isRunningLabAction)

                        Button(AppConstants.Actions.create) {
                            Task { await viewModel.createProductLabSession() }
                        }
                        .disabled(!viewModel.labCanCreateSession)

                        Button(AppConstants.Actions.start) {
                            Task { await viewModel.startProductLabSession() }
                        }
                        .disabled(!viewModel.labCanControlSelectedSession)

                        Button(AppConstants.Actions.stop) {
                            Task { await viewModel.stopProductLabSession() }
                        }
                        .disabled(!viewModel.labCanControlSelectedSession)

                        if viewModel.isRunningLabAction {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(RuntimeLabPanelText.choosingVitalFileForPlayback) {
                            viewModel.chooseVitalFileForProductLabReplay()
                        }
                        Text(vitalFilePlaybackName(viewModel.labVitalFilePath))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button("Replay .vital file") {
                        Task { await viewModel.replayVitalFileWithProductLab() }
                    }
                    .disabled(!viewModel.labCanReplayVitalFile)
                }
            }
        }
    }

    private var browserCard: some View {
        testCard(RuntimeLabPanelText.browserChecks) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(RuntimeLabPanelText.runtimeControlConsole) {
                    linkButton(AppConstants.Product.runtimeControlDevConsoleURL(port: viewModel.settings.runtimeControlPort)) {
                        viewModel.openRuntimeControlDevConsole()
                    }
                    .help(RuntimeLabPanelText.runtimeControlConsoleHelp)
                }
            }
        }
    }

    private func testCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.link)
    }

    private var labActionMessageColor: Color {
        switch viewModel.labActionMessageTone {
        case .failure:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func displayName(_ rawValue: String) -> String {
        rawValue
            .split(separator: "_")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private func vitalFilePlaybackName(_ path: String) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RuntimeLabPanelText.chooseVitalFileForPlayback
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

}
