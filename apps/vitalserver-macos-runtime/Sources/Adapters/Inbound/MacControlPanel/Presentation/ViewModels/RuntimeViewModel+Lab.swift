import Contracts
import Foundation
import RuntimeControl

extension RuntimeViewModel {
    var labCanUseProductLab: Bool {
        capabilities.canUseLab
    }

    var labCanCreateSession: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabScenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && labRecorderCount > 0
    }

    var labCanControlSelectedSession: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var labCanReplayVitalFile: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !labVitalFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func recordLabActionMessage(
        _ value: String,
        tone: RuntimeLabActionMessageTone = .neutral
    ) {
        labActionMessage = value
        labActionMessageTone = tone
    }

    func refreshProductLabScenarios() async {
        recordLabActionMessage(RuntimeLabPanelText.loadingLabScenarios)
        do {
            applyLabScenarios(try await controlClient.loadLabScenarios())
            recordLabActionMessage(RuntimeLabPanelText.loadedLabScenarios(labScenarios.scenarios.count))
        } catch {
            applyLabScenarios(RuntimeLabScenarioList.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func createProductLabSession() async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        guard labCanCreateSession else {
            recordLabActionMessage(RuntimeLabPanelText.chooseLabScenario, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.creatingLabSession)
        message = RuntimeLabPanelText.creatingLabSession
        do {
            applyLabSessionResponse(try await controlClient.createLabSession(RuntimeLabSessionCreateRequest(
                scenarioId: selectedLabScenarioID,
                name: labSessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                recorderCount: labRecorderCount
            )))
            recordLabSessionResult(RuntimeLabPanelText.createdLabSession)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    func startProductLabSession() async {
        await runProductLabSessionCommand(
            progressMessage: RuntimeLabPanelText.startingLabSession,
            action: { try await self.controlClient.startLabSession(sessionId: $0) },
            successMessage: RuntimeLabPanelText.startedLabSession
        )
    }

    func stopProductLabSession() async {
        await runProductLabSessionCommand(
            progressMessage: RuntimeLabPanelText.stoppingLabSession,
            action: { try await self.controlClient.stopLabSession(sessionId: $0) },
            successMessage: RuntimeLabPanelText.stoppedLabSession
        )
    }

    func chooseVitalFileForProductLabReplay() {
        let selectedFiles = nativeShell.chooseVitalFiles(
            prompt: RuntimeLabPanelText.choosingVitalFileForPlayback,
            directoryURL: URL(fileURLWithPath: runtimeSettings.vitalFilesDirectory)
        )
        guard let selectedFile = selectedFiles.first else {
            return
        }
        labVitalFilePath = selectedFile.path
    }

    func replayVitalFileWithProductLab() async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        guard let guestPath = RuntimeLabVitalFilePathPolicy().guestPath(
            hostFilePath: labVitalFilePath,
            hostRootPath: runtimeSettings.vitalFilesDirectory
        ) else {
            recordLabActionMessage(RuntimeLabPanelText.chooseSharedVitalFileForPlayback, tone: .failure)
            message = RuntimeLabPanelText.chooseSharedVitalFileForPlayback
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.replayingLabVitalFile)
        message = RuntimeLabPanelText.replayingLabVitalFile
        do {
            applyLabSessionResponse(try await controlClient.replayLabVitalFile(RuntimeLabVitalFileReplayRequest(
                vitalFilePath: guestPath,
                sessionName: labSessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )))
            recordLabSessionResult(RuntimeLabPanelText.replayedLabVitalFile)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    private func runProductLabSessionCommand(
        progressMessage: String,
        action: @escaping (String) async throws -> RuntimeLabSessionResponse,
        successMessage: (String) -> String
    ) async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        let sessionID = selectedLabSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.noLabSession, tone: .failure)
            message = RuntimeLabPanelText.noLabSession
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(progressMessage)
        message = progressMessage
        do {
            applyLabSessionResponse(try await action(sessionID))
            recordLabSessionResult(successMessage)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    private func applyLabScenarios(_ scenarios: RuntimeLabScenarioList) {
        labScenarios = scenarios
        if selectedLabScenarioID.isEmpty || !scenarios.scenarios.contains(where: { $0.scenarioId == selectedLabScenarioID }) {
            selectedLabScenarioID = scenarios.scenarios.first?.scenarioId ?? ""
        }
    }

    private func applyLabSessionResponse(_ response: RuntimeLabSessionResponse) {
        labSessionResponse = response
        if let session = response.session {
            selectedLabSessionID = session.sessionId
        }
    }

    private func recordLabSessionResult(_ successMessage: (String) -> String) {
        if let session = labSessionResponse.session {
            let actionMessage = successMessage(session.sessionId)
            recordLabActionMessage(actionMessage, tone: labSessionResponse.state == .loaded ? .neutral : .failure)
            message = actionMessage
            return
        }
        let errorMessage = labSessionResponse.readError ?? RuntimeLabPanelText.noLabSession
        recordLabActionMessage(errorMessage, tone: .failure)
        message = errorMessage
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
