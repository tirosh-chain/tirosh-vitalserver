import Foundation
import SwiftUI
import Contracts

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
        .task(id: archiveFinalizationPollKey) {
            await refreshArchiveFinalizationUntilTerminal()
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
                    statusRow(AppConstants.Labels.sessions) {
                        Text(String(viewModel.labSessions.sessions.count))
                            .fontWeight(.medium)
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
                    ForEach(labReadIssues, id: \.self) { readError in
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

                labSessionSection
                labSessionsSection
                selectedLabSessionSection
                selectedLabSessionRecordersSection
                labVitalFileReplaySection
                labResourceManagementSection
            }
        }
    }

    private var labSessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(RuntimeLabPanelText.productLabSession)
                .font(.headline)
            HStack(spacing: 12) {
                Picker(AppConstants.Labels.scenario, selection: $viewModel.selectedLabScenarioID) {
                    if viewModel.labScenarios.scenarios.isEmpty {
                        Text(AppConstants.Values.empty).tag("")
                    } else {
                        ForEach(viewModel.labScenarios.scenarios, id: \.scenarioId) { scenario in
                            Text(scenario.name).tag(scenario.scenarioId)
                        }
                    }
                }
                .frame(maxWidth: 280)
                TextField(RuntimeLabPanelText.labTargetURL, text: $viewModel.labTargetURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
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
                TextField(RuntimeLabPanelText.labSessionBedIDs, text: $viewModel.labSessionBedIDs)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Button(RuntimeLabPanelText.useSelectedLabBed) {
                    viewModel.labSessionBedIDs = viewModel.selectedLabBedID
                }
                .disabled(viewModel.selectedLabBedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

                if viewModel.isRunningLabAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var labSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text(RuntimeLabPanelText.productLabSessions)
                    .font(.headline)
                Text(String(viewModel.labSessions.sessions.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppConstants.Actions.refresh) {
                    Task { await viewModel.refreshProductLabReadModels() }
                }
                .disabled(viewModel.isRunningLabAction)
            }

            Picker(RuntimeLabPanelText.productLabSessions, selection: $viewModel.selectedLabSessionID) {
                if viewModel.labSessions.sessions.isEmpty {
                    Text(AppConstants.Values.empty).tag("")
                } else {
                    ForEach(viewModel.labSessions.sessions, id: \.sessionId) { session in
                        Text("\(session.name ?? session.sessionId) · \(session.state.rawValue)")
                            .tag(session.sessionId)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 520)
            .onChange(of: viewModel.selectedLabSessionID) {
                Task { await viewModel.selectProductLabSession(viewModel.selectedLabSessionID) }
            }

            if let readError = viewModel.labSessions.readError {
                Text(readError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var selectedLabSessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(RuntimeLabPanelText.selectedLabSession)
                .font(.headline)
            if let session = viewModel.selectedLabSession {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                    statusRow(AppConstants.Labels.status) {
                        Text(session.state.rawValue).fontWeight(.medium)
                    }
                    statusRow("Session ID") {
                        Text(session.sessionId)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    statusRow(AppConstants.Labels.scenario) {
                        Text(session.scenarioId).fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.recorders) {
                        Text(String(session.recorderCount)).fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.target) {
                        Text(session.targetURL ?? AppConstants.StatusText.notAvailable)
                            .fontWeight(.medium)
                    }
                    if let finalization = session.archiveFinalization {
                        statusRow(RuntimeLabPanelText.archiveUpload) {
                            Text(finalization.state.rawValue).fontWeight(.medium)
                        }
                        statusRow(RuntimeLabPanelText.archiveUpdated) {
                            Text(finalization.updatedAt ?? AppConstants.StatusText.notAvailable)
                                .fontWeight(.medium)
                        }
                        if let readError = finalization.readError {
                            statusRow(RuntimeLabPanelText.archiveError) {
                                Text(readError)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button(AppConstants.Actions.start) {
                        Task { await viewModel.startProductLabSession() }
                    }
                    .disabled(!viewModel.labCanStartSelectedSession)
                    Button(RuntimeLabPanelText.pause) {
                        Task { await viewModel.stopProductLabSession() }
                    }
                    .disabled(!viewModel.labCanStopSelectedSession)
                    Button(
                        session.state == .finished
                            ? RuntimeLabPanelText.retryUpload
                            : RuntimeLabPanelText.finishAndUpload
                    ) {
                        Task { await viewModel.finishProductLabSession() }
                    }
                    .disabled(!viewModel.labCanFinishSelectedSession)
                }
            } else {
                Text(RuntimeLabPanelText.noLabSession)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var archiveFinalizationPollKey: String {
        guard let session = viewModel.selectedLabSession,
              let finalization = session.archiveFinalization
        else {
            return "none"
        }
        return "\(session.sessionId):\(finalization.state.rawValue)"
    }

    private func refreshArchiveFinalizationUntilTerminal() async {
        guard let finalization = viewModel.selectedLabSession?.archiveFinalization,
              finalizationNeedsPolling(finalization.state)
        else {
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.refreshProductLabReadModels()
            guard let refreshed = viewModel.selectedLabSession?.archiveFinalization,
                  finalizationNeedsPolling(refreshed.state)
            else {
                return
            }
        }
    }

    private func finalizationNeedsPolling(
        _ state: RuntimeLabArchiveFinalizationState
    ) -> Bool {
        switch state {
        case .queued, .processing, .retrying:
            return true
        case .uploaded, .failed, .partial, .missing, .unavailable:
            return false
        }
    }

    private var selectedLabSessionRecordersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text(RuntimeLabPanelText.sessionRecorders)
                    .font(.headline)
                Text(String(viewModel.selectedLabSessionRecorders.count))
                    .foregroundStyle(.secondary)
            }

            if viewModel.selectedLabSessionRecorders.isEmpty {
                Text("No recorders reported for the selected session.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.selectedLabSessionRecorders, id: \.recorderId) { recorder in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(recorder.vrcode).fontWeight(.medium)
                            Text(recorder.state.rawValue).foregroundStyle(.secondary)
                            Spacer()
                            Button(AppConstants.Actions.start) {
                                Task { await viewModel.startProductLabRecorder(recorder.recorderId) }
                            }
                            .disabled(
                                viewModel.isRunningLabAction
                                    || viewModel.selectedLabSession?.state != .running
                                    || recorder.state == .running
                            )
                            Button(AppConstants.Actions.stop) {
                                Task { await viewModel.stopProductLabRecorder(recorder.recorderId) }
                            }
                            .disabled(
                                viewModel.isRunningLabAction
                                    || recorder.state != .running
                            )
                        }
                        Text("\(recorder.recorderId) · \(recorder.bedId) · \(recorder.lastSendState.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var labVitalFileReplaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(RuntimeLabPanelText.vitalFiles)
                .font(.headline)

            Text(RuntimeLabPanelText.uploadToLibrary)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button(RuntimeLabPanelText.chooseVitalFilesForUpload) {
                    viewModel.chooseVitalFilesForProductLabUpload()
                }
                Text(RuntimeLabPanelText.selectedVitalFiles(viewModel.labVitalFileUploadSources.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(RuntimeLabPanelText.uploadToLibrary) {
                    Task { await viewModel.uploadVitalFileToProductLab() }
                }
                .disabled(!viewModel.labCanUploadVitalFile)
            }
            if !viewModel.labVitalFileUploadSources.isEmpty {
                Text(viewModel.labVitalFileUploadSources.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            if !viewModel.labVitalFileImportMessage.isEmpty {
                Text(viewModel.labVitalFileImportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text(RuntimeLabPanelText.replayUploadedFile)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField(RuntimeLabPanelText.vitalFileFilter, text: $viewModel.labVitalFileQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Picker(RuntimeLabPanelText.vitalFileSource, selection: $viewModel.selectedLabVitalFileRelativePath) {
                    if viewModel.labFilteredVitalFiles.isEmpty {
                        Text(AppConstants.Values.empty).tag("")
                    } else {
                        ForEach(viewModel.labFilteredVitalFiles, id: \.relativePath) { vitalFile in
                            Text(vitalFile.relativePath).tag(vitalFile.relativePath)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }

            HStack(spacing: 8) {
                Picker(RuntimeLabPanelText.replayResources, selection: $viewModel.labVitalFileReplayResourceMode) {
                    Text(RuntimeLabPanelText.quickCreateResources).tag(RuntimeLabVitalFileReplayResourceMode.quickCreate)
                    Text(RuntimeLabPanelText.useExistingResources).tag(RuntimeLabVitalFileReplayResourceMode.existing)
                }
                .frame(maxWidth: 220)

                if viewModel.labVitalFileReplayResourceMode == .existing {
                    Picker(RuntimeLabPanelText.labBedManagement, selection: $viewModel.selectedLabBedID) {
                        ForEach(viewModel.labBeds.beds, id: \.bedId) { bed in
                            Text(bed.name).tag(bed.bedId)
                        }
                    }
                    .frame(maxWidth: 220)
                    Picker(RuntimeLabPanelText.labRecorderManagement, selection: $viewModel.selectedLabRecorderID) {
                        ForEach(
                            viewModel.labRecorders.recorders.filter { $0.bedId == viewModel.selectedLabBedID },
                            id: \.recorderId
                        ) { recorder in
                            Text(recorder.vrcode).tag(recorder.recorderId)
                        }
                    }
                    .frame(maxWidth: 220)
                }
            }

            HStack(spacing: 8) {
                Picker(RuntimeLabPanelText.repeatMode, selection: $viewModel.labVitalFileReplayRepeatMode) {
                    Text(RuntimeLabPanelText.repeatOnce).tag(RuntimeLabVitalFileReplayRepeatMode.once)
                    Text(RuntimeLabPanelText.repeatCount).tag(RuntimeLabVitalFileReplayRepeatMode.count)
                    Text(RuntimeLabPanelText.repeatContinuous).tag(RuntimeLabVitalFileReplayRepeatMode.continuous)
                }
                .frame(maxWidth: 220)
                if viewModel.labVitalFileReplayRepeatMode == .count {
                    Stepper(
                        RuntimeLabPanelText.repeatTimes(viewModel.labVitalFileReplayCount),
                        value: $viewModel.labVitalFileReplayCount,
                        in: 2...10_000
                    )
                    .frame(maxWidth: 180)
                }
                Button(RuntimeLabPanelText.replayUploadedFile) {
                    Task { await viewModel.replayVitalFileWithProductLab() }
                }
                .disabled(!viewModel.labCanReplayVitalFile)
            }
        }
    }

    private var labResourceManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(RuntimeLabPanelText.productLabResources)
                .font(.headline)
            labBedManagementSection
            labRecorderManagementSection
        }
    }

    private var labBedManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(RuntimeLabPanelText.labBedManagement)
                    .font(.headline)
                Text("\(viewModel.labBeds.beds.count)")
                    .foregroundStyle(.secondary)
                Stepper(
                    "\(AppConstants.Actions.create): \(viewModel.labBedCount)",
                    value: $viewModel.labBedCount,
                    in: 1...200
                )
                .frame(width: 160, alignment: .trailing)
                TextField("Prefix", text: $viewModel.labBedPrefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            HStack(spacing: 8) {
                Picker(RuntimeLabPanelText.labBedManagement, selection: $viewModel.selectedLabBedID) {
                    if viewModel.labBeds.beds.isEmpty {
                        Text(AppConstants.Values.empty).tag("")
                    } else {
                        ForEach(viewModel.labBeds.beds, id: \.bedId) { bed in
                            Text("\(bed.name) · \(bed.sessionId)").tag(bed.bedId)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)

                Button(AppConstants.Actions.create) {
                    Task { await viewModel.createProductLabBeds() }
                }
                .disabled(!viewModel.labCanCreateBeds)

                Button(AppConstants.Actions.delete) {
                    Task { await viewModel.deleteSelectedProductLabBed() }
                }
                .disabled(!viewModel.labCanDeleteSelectedBed)

                Button("Reset") {
                    Task { await viewModel.resetProductLabBeds() }
                }
                .disabled(viewModel.isRunningLabAction || !viewModel.labCanUseProductLab)
            }
        }
    }

    private var labRecorderManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                Text(RuntimeLabPanelText.labRecorderManagement)
                    .font(.headline)
                Text("\(viewModel.labRecorders.recorders.count)")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Picker(RuntimeLabPanelText.labRecorderManagement, selection: $viewModel.selectedLabRecorderID) {
                    if viewModel.labRecorders.recorders.isEmpty {
                        Text(AppConstants.Values.empty).tag("")
                    } else {
                        ForEach(viewModel.labRecorders.recorders, id: \.recorderId) { recorder in
                            Text("\(recorder.vrcode) · \(recorder.lastSendState.rawValue)").tag(recorder.recorderId)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)

                Button(AppConstants.Actions.create) {
                    Task { await viewModel.createProductLabRecorderForSelectedBed() }
                }
                .disabled(!viewModel.labCanCreateRecorder)

                Button(AppConstants.Actions.delete) {
                    Task { await viewModel.deleteSelectedProductLabRecorder() }
                }
                .disabled(!viewModel.labCanDeleteSelectedRecorder)

                Button("Reset") {
                    Task { await viewModel.resetProductLabRecorders() }
                }
                .disabled(viewModel.isRunningLabAction || !viewModel.labCanUseProductLab)
            }
            if let recorder = viewModel.labRecorders.recorders.first(where: { $0.recorderId == viewModel.selectedLabRecorderID }) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                    statusRow(RuntimeLabPanelText.messagesSent) {
                        Text(String(recorder.messagesSent))
                            .fontWeight(.medium)
                    }
                    statusRow(RuntimeLabPanelText.lastSend) {
                        Text(recorder.lastSendError ?? recorder.lastSendState.rawValue)
                            .fontWeight(.medium)
                            .foregroundStyle(recorder.lastSendState == .failed ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    private var labReadIssues: [String] {
        let rawIssues = [
            viewModel.labScenarios.readError,
            viewModel.labSessions.readError,
            viewModel.labSessionResponse.readError,
            viewModel.labBeds.readError,
            viewModel.labRecorders.readError,
            viewModel.labVitalFiles.readError,
        ]
        var seen: Set<String> = []
        return rawIssues.compactMap { issue in
            let value = labReadIssueDisplayText(issue)
            guard !value.isEmpty, !seen.contains(value) else {
                return nil
            }
            seen.insert(value)
            return value
        }
    }

    private func labReadIssueDisplayText(_ issue: String?) -> String {
        let value = issue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            return ""
        }
        if value.contains("missing-vm-ip") {
            return "Product Lab unavailable: guest address is unavailable (missing-vm-ip)."
        }
        return value
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

}
