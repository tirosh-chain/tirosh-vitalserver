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
            && !resolvedLabVitalFileGuestPath().isEmpty
    }

    var labCanUploadVitalFile: Bool {
        labCanReplayVitalFile
            && !labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var labFilteredVitalFiles: [RuntimeLabVitalFile] {
        let query = labVitalFileQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return labVitalFiles.vitalFiles
        }
        return labVitalFiles.vitalFiles.filter { vitalFile in
            vitalFile.displayName.lowercased().contains(query)
                || vitalFile.relativePath.lowercased().contains(query)
        }
    }

    var labCanCreateBeds: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && labBedCount > 0
    }

    var labCanCreateRecorder: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabBedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var labCanDeleteSelectedBed: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabBedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var labCanDeleteSelectedRecorder: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabRecorderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            applyLabVitalFiles(try await controlClient.loadLabVitalFiles())
            await refreshProductLabReadModels()
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
                recorderCount: labRecorderCount,
                targetURL: labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )))
            await refreshProductLabReadModels()
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
        selectedLabVitalFileGuestPath = ""
    }

    func replayVitalFileWithProductLab() async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        let guestPath = resolvedLabVitalFileGuestPath()
        guard !guestPath.isEmpty else {
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
                sessionName: labSessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                targetURL: labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )))
            if let sessionID = labSessionResponse.session?.sessionId {
                applyLabSessionResponse(try await controlClient.startLabSession(sessionId: sessionID))
            }
            await refreshProductLabReadModels()
            recordLabSessionResult(RuntimeLabPanelText.replayedLabVitalFile)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    func uploadVitalFileToProductLab() async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        let guestPath = resolvedLabVitalFileGuestPath()
        guard !guestPath.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseSharedVitalFileForPlayback, tone: .failure)
            message = RuntimeLabPanelText.chooseSharedVitalFileForPlayback
            return
        }
        let targetURL = labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.labTargetURLRequired, tone: .failure)
            message = RuntimeLabPanelText.labTargetURLRequired
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.uploadingLabVitalFile)
        message = RuntimeLabPanelText.uploadingLabVitalFile
        do {
            labVitalFileUploadResponse = try await controlClient.uploadLabVitalFile(RuntimeLabVitalFileUploadRequest(
                vitalFilePath: guestPath,
                targetURL: targetURL,
                endpoint: "/upload"
            ))
            recordLabUploadResult()
        } catch {
            labVitalFileUploadResponse = RuntimeLabVitalFileUploadResponse.unavailable(readError: error.localizedDescription)
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    func refreshProductLabReadModels() async {
        guard labCanUseProductLab else {
            return
        }
        do {
            applyLabBeds(try await controlClient.loadLabBeds())
            applyLabRecorders(try await controlClient.loadLabRecorders())
        } catch {
            labBeds = RuntimeLabBedList.unavailable(readError: error.localizedDescription)
            labRecorders = RuntimeLabRecorderList.unavailable(readError: error.localizedDescription)
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func createProductLabBeds() async {
        guard labCanCreateBeds else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.creatingLabBeds)
        do {
            applyLabBeds(try await controlClient.createLabBeds(RuntimeLabBedCreateRequest(
                count: labBedCount,
                prefix: labBedPrefix.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                targetURL: labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )))
            applyLabRecorders(try await controlClient.loadLabRecorders())
            recordLabActionMessage(RuntimeLabPanelText.createdLabBeds(labBeds.beds.count))
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func deleteSelectedProductLabBed() async {
        let bedID = selectedLabBedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard labCanDeleteSelectedBed, !bedID.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseLabBed, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.deletingLabBed)
        do {
            applyLabBeds(try await controlClient.deleteLabBeds(RuntimeLabBedDeleteRequest(bedIds: [bedID])))
            applyLabRecorders(try await controlClient.loadLabRecorders())
            recordLabActionMessage(RuntimeLabPanelText.deletedLabBed)
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func resetProductLabBeds() async {
        guard labCanUseProductLab, !isRunningLabAction else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.resettingLabBeds)
        do {
            applyLabBeds(try await controlClient.resetLabBeds())
            applyLabRecorders(try await controlClient.loadLabRecorders())
            selectedLabSessionID = ""
            recordLabActionMessage(RuntimeLabPanelText.resetLabBeds)
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func createProductLabRecorderForSelectedBed() async {
        let bedID = selectedLabBedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard labCanCreateRecorder, !bedID.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseLabBed, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.creatingLabRecorder)
        do {
            applyLabRecorders(try await controlClient.createLabRecorders(RuntimeLabRecorderCreateRequest(bedIds: [bedID])))
            recordLabActionMessage(RuntimeLabPanelText.createdLabRecorder)
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func deleteSelectedProductLabRecorder() async {
        let recorderID = selectedLabRecorderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard labCanDeleteSelectedRecorder, !recorderID.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseLabRecorder, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.deletingLabRecorder)
        do {
            applyLabRecorders(try await controlClient.deleteLabRecorders(RuntimeLabRecorderDeleteRequest(recorderIds: [recorderID])))
            recordLabActionMessage(RuntimeLabPanelText.deletedLabRecorder)
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func resetProductLabRecorders() async {
        guard labCanUseProductLab, !isRunningLabAction else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            return
        }
        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.resettingLabRecorders)
        do {
            applyLabRecorders(try await controlClient.resetLabRecorders())
            recordLabActionMessage(RuntimeLabPanelText.resetLabRecorders)
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
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
            await refreshProductLabReadModels()
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

    private func applyLabVitalFiles(_ vitalFiles: RuntimeLabVitalFileList) {
        labVitalFiles = vitalFiles
        if selectedLabVitalFileGuestPath.isEmpty
            || !vitalFiles.vitalFiles.contains(where: { $0.guestPath == selectedLabVitalFileGuestPath })
        {
            selectedLabVitalFileGuestPath = vitalFiles.vitalFiles.first?.guestPath ?? ""
        }
    }

    private func applyLabSessionResponse(_ response: RuntimeLabSessionResponse) {
        labSessionResponse = response
        if let session = response.session {
            selectedLabSessionID = session.sessionId
        }
    }

    private func applyLabBeds(_ response: RuntimeLabBedList) {
        labBeds = response
        if selectedLabBedID.isEmpty || !response.beds.contains(where: { $0.bedId == selectedLabBedID }) {
            selectedLabBedID = response.beds.first?.bedId ?? ""
        }
        if selectedLabSessionID.isEmpty,
           let sessionID = response.beds.first(where: { $0.bedId == selectedLabBedID })?.sessionId
        {
            selectedLabSessionID = sessionID
        }
    }

    private func applyLabRecorders(_ response: RuntimeLabRecorderList) {
        labRecorders = response
        if selectedLabRecorderID.isEmpty || !response.recorders.contains(where: { $0.recorderId == selectedLabRecorderID }) {
            selectedLabRecorderID = response.recorders.first?.recorderId ?? ""
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

    private func recordLabUploadResult() {
        if let upload = labVitalFileUploadResponse.upload, upload.ok {
            let actionMessage = RuntimeLabPanelText.uploadedLabVitalFile(upload.filename)
            recordLabActionMessage(actionMessage)
            message = actionMessage
            return
        }
        let errorMessage = labVitalFileUploadResponse.readError ?? RuntimeLabPanelText.uploadFailed
        recordLabActionMessage(errorMessage, tone: .failure)
        message = errorMessage
    }

    private func resolvedLabVitalFileGuestPath() -> String {
        let selectedGuestPath = selectedLabVitalFileGuestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedGuestPath.isEmpty {
            return selectedGuestPath
        }
        return RuntimeLabVitalFilePathPolicy().guestPath(
            hostFilePath: labVitalFilePath,
            hostRootPath: runtimeSettings.vitalFilesDirectory
        ) ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
