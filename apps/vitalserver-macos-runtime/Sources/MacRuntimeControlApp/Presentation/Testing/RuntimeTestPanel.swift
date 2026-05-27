import SwiftUI
import RuntimeControl

struct RuntimeTestPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RuntimeTestPanelText.summary)
                        .font(.headline)
                    Text(RuntimeTestPanelText.description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                browserCard
                testkitCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
        }
        .task {
            await viewModel.refreshTestKitStatus()
        }
    }

    private var browserCard: some View {
        testCard(RuntimeTestPanelText.browserChecks) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(RuntimeTestPanelText.runtimeControlConsole) {
                    linkButton(RuntimeDevelopmentAPIConstants.devConsoleURL) {
                        viewModel.openRuntimeControlDevConsole()
                    }
                    .help(RuntimeTestPanelText.runtimeControlConsoleHelp)
                }
            }
        }
    }

    private var testkitCard: some View {
        testCard(RuntimeTestPanelText.testkitService) {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    statusRow(AppConstants.Labels.enabled) {
                        Text(viewModel.testKitStatus.enabled ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.status) {
                        Text(displayName(viewModel.testKitStatus.state))
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.serviceName) {
                        Text(viewModel.testKitStatus.serviceName ?? AppConstants.Values.empty)
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.url) {
                        Text(viewModel.testKitStatus.apiBaseURL ?? AppConstants.Values.empty)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    statusRow(AppConstants.Labels.sessions) {
                        Text(String(viewModel.testKitStatus.sessions.count))
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.session) {
                        selectedSessionPicker
                    }
                    statusRow(AppConstants.Labels.recorders) {
                        Text(String(viewModel.selectedTestKitSession?.recorders.count ?? 0))
                        .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.messages) {
                        Text(String(viewModel.selectedTestKitSession?.messagesSent ?? 0))
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.target) {
                        Text(viewModel.testKitStatus.recorderTargetURL ?? AppConstants.Values.empty)
                            .fontWeight(.medium)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Picker(AppConstants.Labels.scenario, selection: $viewModel.testKitScenario) {
                        ForEach(RuntimeTestKitScenario.allCases, id: \.self) { scenario in
                            Text(displayName(scenario)).tag(scenario)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(AppConstants.Labels.signal, selection: $viewModel.testKitSignalProfile) {
                        ForEach(RuntimeTestKitSignalProfile.allCases, id: \.self) { profile in
                            Text(displayName(profile)).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(AppConstants.Labels.vrcodeOptional, text: $viewModel.testKitVrcode)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!viewModel.testKitStatus.enabled || viewModel.isRunningTestKitAction)

                HStack(spacing: 8) {
                    Button(AppConstants.Actions.refresh) {
                        Task { await viewModel.refreshTestKitStatus() }
                    }
                    .disabled(viewModel.isRunningTestKitAction)

                    Button(AppConstants.Actions.start) {
                        Task { await viewModel.startVirtualRecorderSession() }
                    }
                    .disabled(!viewModel.testKitCanStart)

                    Button(AppConstants.Actions.stop) {
                        Task { await viewModel.stopVirtualRecorderSession() }
                    }
                    .disabled(!viewModel.testKitCanStop)

                    if viewModel.isRunningTestKitAction {
                        ProgressView()
                            .controlSize(.small)
                    }
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

    private var selectedSessionPicker: some View {
        Picker(AppConstants.Labels.session, selection: $viewModel.selectedTestKitSessionID) {
            if viewModel.testKitStatus.sessions.isEmpty {
                Text(AppConstants.Values.empty).tag("")
            }
            ForEach(viewModel.testKitStatus.sessions, id: \.id) { session in
                Text(sessionLabel(session)).tag(session.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 360, alignment: .leading)
        .disabled(viewModel.testKitStatus.sessions.isEmpty || viewModel.isRunningTestKitAction)
    }

    private func sessionLabel(_ session: RuntimeTestKitSession) -> String {
        let recorder = session.recorders.first?.vrcode ?? session.vrcode ?? session.id
        return "\(recorder) · \(displayName(session.state))"
    }

    private func displayName(_ state: RuntimeTestKitState) -> String {
        displayName(state.rawValue)
    }

    private func displayName(_ scenario: RuntimeTestKitScenario) -> String {
        displayName(scenario.rawValue)
    }

    private func displayName(_ profile: RuntimeTestKitSignalProfile) -> String {
        displayName(profile.rawValue)
    }

    private func displayName(_ rawValue: String) -> String {
        rawValue
            .split(separator: "_")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
