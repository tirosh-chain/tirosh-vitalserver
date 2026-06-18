import Foundation
import SwiftUI
import RuntimeControl
import Errors

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
            await refreshTestKitStatusLoop()
        }
    }

    private var browserCard: some View {
        testCard(RuntimeTestPanelText.browserChecks) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(RuntimeTestPanelText.runtimeControlConsole) {
                    linkButton(AppConstants.Product.runtimeControlDevConsoleURL(port: viewModel.settings.runtimeControlPort)) {
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
                    if !viewModel.testKitActionMessage.isEmpty {
                        statusRow(AppConstants.Labels.operation) {
                            Text(viewModel.testKitActionMessage)
                                .fontWeight(.medium)
                                .foregroundStyle(actionMessageColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                    statusRow(AppConstants.Labels.beds) {
                        Text(String(viewModel.testKitStatus.beds.count))
                            .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.recorders) {
                        Text(String(totalRecorders))
                        .fontWeight(.medium)
                    }
                    statusRow(AppConstants.Labels.messages) {
                        Text(String(totalMessages))
                            .fontWeight(.medium)
                    }
                    if let lastError = visibleLastError,
                       !lastError.isEmpty {
                        statusRow(AppConstants.Labels.lastError) {
                            Text(lastError)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    statusRow(AppConstants.Labels.target) {
                        Text(viewModel.testKitStatus.recorderTargetURL ?? AppConstants.Values.empty)
                            .fontWeight(.medium)
                    }
                }

                Divider()

                bedList

                Divider()

                virtualRecorderSession

                Divider()

                manualVitalUpload

                Divider()

                sessionList

                Divider()

                orphanCleanup
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

    private func testKitIntegerStepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        displayValue: String
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Stepper(displayValue, value: value, in: range, step: step)
                .monospacedDigit()
                .frame(width: 180, alignment: .trailing)
        }
    }

    private func testKitDoubleStepper(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        displayValue: String
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Stepper(displayValue, value: value, in: range, step: step)
                .monospacedDigit()
                .frame(width: 180, alignment: .trailing)
        }
    }

    private var bedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(AppConstants.Labels.bedSetup)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(AppConstants.Actions.create) {
                    Task { await viewModel.createTestKitBeds() }
                }
                .disabled(!viewModel.testKitStatus.enabled || viewModel.isRunningTestKitAction)
                Button(AppConstants.Actions.reset) {
                    Task { await viewModel.resetTestKitBeds() }
                }
                .disabled(!viewModel.testKitCanResetBeds)
            }

            bedCreationControls

            if viewModel.testKitStatus.beds.isEmpty {
                Text(RuntimeTestPanelText.noBeds)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                Divider()
                    .padding(.vertical, 4)

                bedSelectionSection
            }
        }
    }

    private var bedCreationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            testKitIntegerStepper(
                AppConstants.Labels.bedCount,
                value: $viewModel.testKitBedCount,
                range: 1...200,
                displayValue: viewModel.testKitAppendRandomBedSuffix
                    ? String(viewModel.testKitBedCount)
                    : "1"
            )
            .disabled(!viewModel.testKitAppendRandomBedSuffix)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AppConstants.Labels.bedPrefix)
                    .foregroundStyle(.secondary)
                TextField(AppConstants.Labels.bedPrefix, text: $viewModel.testKitBedPrefix)
                    .textFieldStyle(.roundedBorder)
                Toggle(
                    AppConstants.Labels.randomBedSuffix,
                    isOn: $viewModel.testKitAppendRandomBedSuffix
                )
                .fixedSize()
            }
        }
        .disabled(!viewModel.testKitStatus.enabled || viewModel.isRunningTestKitAction)
    }

    private var bedSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppConstants.Labels.bedSelection)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(RuntimeTestPanelText.chooseBeds)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RuntimeTestPanelText.selectedBeds(
                    viewModel.selectedTestKitBedCount,
                    viewModel.testKitRecorderCount,
                    viewModel.availableTestKitBedCount
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(viewModel.testKitStatus.beds) { bed in
                bedSelectionRow(bed)
            }
        }
    }

    private func bedSelectionRow(_ bed: RuntimeTestKitBed) -> some View {
        let isActive = viewModel.testKitBedIsActive(bed.roomName)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { viewModel.testKitBedIsSelected(bed.roomName) },
                set: { viewModel.setTestKitBedSelection(bed.roomName, selected: $0) }
            ))
            .labelsHidden()
            .disabled(isActive || viewModel.isRunningTestKitAction)
            .help(isActive ? RuntimeTestPanelText.activeBedHelp : "")

            VStack(alignment: .leading, spacing: 2) {
                Text(bed.roomName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(bed.bedID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if isActive {
                Text(RuntimeTestPanelText.activeBed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(AppConstants.Actions.delete) {
                Task { await viewModel.deleteTestKitBed(bed) }
            }
            .disabled(!viewModel.testKitCanDeleteBed(bed.roomName))
            .help(isActive ? RuntimeTestPanelText.activeBedHelp : "")
        }
        .padding(.vertical, 2)
    }

    private var virtualRecorderSession: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppConstants.Labels.virtualVRecorderSession)
                .font(.subheadline)
                .fontWeight(.semibold)

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

            testKitIntegerStepper(
                AppConstants.Labels.recorderCount,
                value: $viewModel.testKitRecorderCount,
                range: 1...200,
                displayValue: String(viewModel.testKitRecorderCount)
            )

            Text(RuntimeTestPanelText.selectedBeds(
                viewModel.selectedTestKitBedCount,
                viewModel.testKitRecorderCount,
                viewModel.availableTestKitBedCount
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if viewModel.testKitRecorderCount > 1 {
                Text(RuntimeTestPanelText.sharedContainerIPWarning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(AppConstants.Labels.trafficProfile)
                .font(.subheadline)
                .fontWeight(.semibold)

            testKitDoubleStepper(
                AppConstants.Labels.interval,
                value: $viewModel.testKitIntervalSeconds,
                range: 0.1...60,
                step: 0.1,
                displayValue: secondsText(viewModel.testKitIntervalSeconds)
            )

            testKitDoubleStepper(
                AppConstants.Labels.duration,
                value: $viewModel.testKitDurationSeconds,
                range: 0...86_400,
                step: 10,
                displayValue: limitText(seconds: viewModel.testKitDurationSeconds)
            )

            testKitIntegerStepper(
                AppConstants.Labels.maxMessages,
                value: $viewModel.testKitMaxMessages,
                range: 0...1_000_000,
                step: 10,
                displayValue: viewModel.testKitMaxMessages > 0
                    ? String(viewModel.testKitMaxMessages)
                    : AppConstants.Values.unlimited
            )

            HStack(spacing: 16) {
                Toggle(AppConstants.Labels.shiftTime, isOn: $viewModel.testKitShiftTime)
                Toggle(AppConstants.Labels.generateFrames, isOn: $viewModel.testKitGenerateFrames)
            }

            TextField(AppConstants.Labels.vrcodeOptional, text: $viewModel.testKitVrcode)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(AppConstants.Actions.refresh) {
                    Task {
                        await viewModel.refreshTestKitStatus()
                        viewModel.recordTestKitActionMessage(RuntimeTestPanelText.refreshedStatus)
                    }
                }
                .disabled(viewModel.isRunningTestKitAction)

                Button(AppConstants.Actions.start) {
                    Task { await viewModel.startVirtualRecorderSession() }
                }
                .disabled(!viewModel.testKitCanStart)
                .help(startHelpText)

                Button(AppConstants.Actions.reset) {
                    Task { await viewModel.resetVirtualRecorderSessions() }
                }
                .disabled(viewModel.isRunningTestKitAction || viewModel.testKitStatus.sessions.isEmpty)

                if viewModel.isRunningTestKitAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppConstants.Labels.sessions)
                .font(.subheadline)
                .fontWeight(.semibold)
            if viewModel.testKitStatus.sessions.isEmpty {
                Text(AppConstants.Values.empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.testKitStatus.sessions, id: \.id) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private var manualVitalUpload: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppConstants.Labels.sectionVitalFileUpload)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(RuntimeTestPanelText.manualVitalUploadDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(AppConstants.Actions.uploadVitalFiles) {
                Task { await viewModel.uploadVitalFilesFromTestTab() }
            }
            .disabled(!viewModel.testKitStatus.enabled || viewModel.isRunningTestKitAction)
        }
    }

    private func sessionRow(_ session: RuntimeTestKitSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionTitle(session))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sessionDetail(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            sessionControls(session)
            Button(AppConstants.Actions.delete) {
                Task { await viewModel.deleteVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(viewModel.isRunningTestKitAction)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionControls(_ session: RuntimeTestKitSession) -> some View {
        switch viewModel.testKitSessionControlState(session) {
        case .running:
            Button(AppConstants.Actions.pause) {
                Task { await viewModel.pauseVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(viewModel.isRunningTestKitAction)
            Button(AppConstants.Actions.stop) {
                Task { await viewModel.stopVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(viewModel.isRunningTestKitAction)
        case .paused:
            Button(AppConstants.Actions.resume) {
                Task { await viewModel.resumeVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(viewModel.isRunningTestKitAction)
            Button(AppConstants.Actions.stop) {
                Task { await viewModel.stopVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(viewModel.isRunningTestKitAction)
        case .terminal:
            Button(AppConstants.Actions.restart) {
                Task { await viewModel.restartVirtualRecorderSession(session: session) }
            }
            .disabled(viewModel.isRunningTestKitAction || !viewModel.testKitSessionIsRestartable(session))
            .help(restartHelpText(session))
        case .unavailable:
            Button(AppConstants.Actions.stop) {
                Task { await viewModel.stopVirtualRecorderSession(sessionID: session.id) }
            }
            .disabled(true)
        }
    }

    private var orphanCleanup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RuntimeTestPanelText.orphanCleanup)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(RuntimeTestPanelText.orphanCleanupDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField(AppConstants.Labels.orphanVrcode, text: $viewModel.testKitOrphanVrcode)
                    .textFieldStyle(.roundedBorder)
                Button(AppConstants.Actions.deleteVRecorder) {
                    Task { await viewModel.deleteOrphanVirtualRecorder() }
                }
                .disabled(!canDeleteOrphanVRecorder)
            }
        }
    }

    private var canDeleteOrphanVRecorder: Bool {
        viewModel.testKitStatus.enabled
            && !viewModel.isRunningTestKitAction
            && !viewModel.testKitOrphanVrcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var startHelpText: String {
        if viewModel.testKitStatus.beds.isEmpty {
            return RuntimeTestPanelText.noBeds
        }
        if viewModel.selectedTestKitBedCount < viewModel.testKitRecorderCount {
            return RuntimeTestPanelText.insufficientSelectedBeds(
                viewModel.selectedTestKitBedCount,
                viewModel.testKitRecorderCount
            )
        }
        return ""
    }

    private var totalRecorders: Int {
        viewModel.testKitStatus.sessions.reduce(0) { total, session in
            total + session.recorders.count
        }
    }

    private var totalMessages: Int {
        viewModel.testKitStatus.sessions.reduce(0) { total, session in
            total + session.messagesSent
        }
    }

    private var visibleLastError: String? {
        if let selectedError = viewModel.selectedTestKitSession?.lastError, !selectedError.isEmpty {
            return selectedError
        }
        if let failedError = viewModel.testKitStatus.sessions.first(where: { $0.lastError?.isEmpty == false })?.lastError {
            return failedError
        }
        return viewModel.testKitStatus.lastError
    }

    private var actionMessageColor: Color {
        switch viewModel.testKitActionMessageTone {
        case .failure:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func sessionTitle(_ session: RuntimeTestKitSession) -> String {
        let recorder = session.recorders.first?.vrcode ?? session.vrcode ?? session.id
        return "\(recorder) · \(displayName(session.state))"
    }

    private func sessionDetail(_ session: RuntimeTestKitSession) -> String {
        [
            "\(AppConstants.Labels.messages): \(session.messagesSent)",
            "\(AppConstants.Labels.bytes): \(session.bytesSent)",
            "\(AppConstants.Labels.recorders): \(session.recorders.count)/\(session.recordersRequested)",
            "\(AppConstants.Labels.beds): \(session.bedRoomNames.count)",
            "\(AppConstants.Labels.interval): \(secondsText(session.intervalSeconds))",
            vitalDetail(session.vital),
            session.cleanupErrors.isEmpty ? nil : "Cleanup errors: \(session.cleanupErrors.count)",
            session.lastError.map { "\(AppConstants.Labels.lastError): \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func vitalDetail(_ vital: RuntimeTestKitSessionVitalState?) -> String? {
        guard let vital else {
            return nil
        }
        var parts = [
            "export \(displayName(vital.exportStatus))",
            "upload \(displayName(vital.uploadStatus))",
        ]
        if let artifact = vital.artifact {
            parts.append("\(artifact.filename) \(byteText(artifact.sizeBytes))")
        }
        if let exportError = vital.exportError, !exportError.isEmpty {
            parts.append("export error: \(exportError)")
        }
        if let uploadError = vital.uploadError, !uploadError.isEmpty {
            parts.append("upload error: \(uploadError)")
        }
        return "Vital: \(parts.joined(separator: ", "))"
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func restartHelpText(_ session: RuntimeTestKitSession) -> String {
        let requiredBeds = viewModel.testKitRestartRequiredBedCount(session)
        guard viewModel.selectedTestKitBedCount < requiredBeds else {
            return ""
        }
        return RuntimeTestPanelText.insufficientSelectedBeds(
            viewModel.selectedTestKitBedCount,
            requiredBeds
        )
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

    private func secondsText(_ seconds: Double) -> String {
        String(format: "%.1f s", seconds)
    }

    private func limitText(seconds: Double) -> String {
        seconds > 0 ? secondsText(seconds) : AppConstants.Values.unlimited
    }

    private func refreshTestKitStatusLoop() async {
        await viewModel.refreshTestKitStatus()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await viewModel.refreshTestKitStatus()
        }
    }
}
