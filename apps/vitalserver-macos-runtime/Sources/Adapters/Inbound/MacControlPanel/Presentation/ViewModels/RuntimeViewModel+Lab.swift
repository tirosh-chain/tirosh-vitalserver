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

    var labCanStartSelectedSession: Bool {
        guard labCanControlSelectedSession, let session = selectedLabSession else {
            return false
        }
        return session.state == .accepted || session.state == .stopped
    }

    var labCanStopSelectedSession: Bool {
        labCanControlSelectedSession && selectedLabSession?.state == .running
    }

    var labCanFinishSelectedSession: Bool {
        guard labCanControlSelectedSession, let session = selectedLabSession else {
            return false
        }
        return session.state == .running || session.state == .stopped || session.state == .finished
    }

    var selectedLabSession: RuntimeLabSession? {
        if let session = labSessionResponse.session,
           session.sessionId == selectedLabSessionID
        {
            return session
        }
        return labSessions.sessions.first { $0.sessionId == selectedLabSessionID }
    }

    var selectedLabSessionRecorders: [RuntimeLabRecorder] {
        labRecorders.recorders.filter { $0.sessionId == selectedLabSessionID }
    }

    var labCanReplayVitalFile: Bool {
        labCanUseProductLab
            && !isRunningLabAction
            && !selectedLabVitalFileRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (labVitalFileReplayResourceMode == .quickCreate || replayExistingResourceSelectionIsValid)
            && (labVitalFileReplayRepeatMode != .count || labVitalFileReplayCount >= 2)
    }

    var labCanUploadVitalFile: Bool {
        !isRunningLabAction && !labVitalFileUploadSources.isEmpty
    }

    private var replayExistingResourceSelectionIsValid: Bool {
        guard let recorder = labRecorders.recorders.first(where: {
            $0.recorderId == selectedLabRecorderID
        }) else {
            return false
        }
        return !selectedLabBedID.isEmpty && recorder.bedId == selectedLabBedID
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
        var failures: [String] = []

        do {
            applyLabScenarios(try await controlClient.loadLabScenarios())
        } catch {
            applyLabScenarios(RuntimeLabScenarioList.unavailable(readError: error.localizedDescription))
            failures.append("scenarios: \(error.localizedDescription)")
        }

        do {
            applyLabVitalFiles(try await controlClient.loadLabVitalFiles())
        } catch {
            applyLabVitalFiles(RuntimeLabVitalFileList.unavailable(readError: error.localizedDescription))
            failures.append("vital files: \(error.localizedDescription)")
        }

        await refreshProductLabReadModels()

        if failures.isEmpty {
            recordLabActionMessage(RuntimeLabPanelText.loadedLabScenarios(labScenarios.scenarios.count))
            return
        }

        recordLabActionMessage(failures.joined(separator: ", "), tone: .failure)
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
            let bedIDs = labSessionBedIDsList()
            let recorderCount = bedIDs.isEmpty ? labRecorderCount : bedIDs.count
            applyLabSessionResponse(try await controlClient.createLabSession(RuntimeLabSessionCreateRequest(
                scenarioId: selectedLabScenarioID,
                name: labSessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                recorderCount: recorderCount,
                targetURL: labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                bedIds: bedIDs.isEmpty ? nil : bedIDs
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

    func finishProductLabSession() async {
        await runProductLabSessionCommand(
            progressMessage: RuntimeLabPanelText.finishingLabSession,
            action: { try await self.controlClient.finishLabSession(sessionId: $0) },
            successMessage: RuntimeLabPanelText.finishedLabSession
        )
    }

    func selectProductLabSession(_ sessionID: String) async {
        selectedLabSessionID = sessionID
        guard !sessionID.isEmpty else {
            labSessionResponse = RuntimeLabSessionResponse.unavailable(
                readError: RuntimeLabPanelText.noLabSession
            )
            return
        }
        do {
            applyLabSessionResponse(try await controlClient.loadLabSession(sessionId: sessionID))
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }
    }

    func startProductLabRecorder(_ recorderID: String) async {
        await runProductLabRecorderCommand(recorderID: recorderID, start: true)
    }

    func stopProductLabRecorder(_ recorderID: String) async {
        await runProductLabRecorderCommand(recorderID: recorderID, start: false)
    }

    func chooseVitalFilesForProductLabUpload() {
        let selectedFiles = nativeShell.chooseVitalFiles(
            prompt: RuntimeLabPanelText.chooseVitalFilesForUpload,
            directoryURL: nil
        )
        guard !selectedFiles.isEmpty else {
            return
        }
        labVitalFileUploadSources = selectedFiles
        labVitalFileImportMessage = ""
    }

    func replayVitalFileWithProductLab() async {
        guard labCanUseProductLab else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            message = RuntimeLabPanelText.labCapabilityUnavailable
            return
        }
        let relativePath = selectedLabVitalFileRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relativePath.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseUploadedVitalFile, tone: .failure)
            message = RuntimeLabPanelText.chooseUploadedVitalFile
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.replayingLabVitalFile)
        message = RuntimeLabPanelText.replayingLabVitalFile
        do {
            applyLabSessionResponse(try await controlClient.replayLabVitalFile(RuntimeLabVitalFileReplayRequest(
                vitalFileRelativePath: relativePath,
                sessionName: labSessionName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                targetURL: labTargetURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                resourceSelection: replayResourceSelection(),
                repeatPolicy: RuntimeLabVitalFileReplayPolicy(
                    mode: labVitalFileReplayRepeatMode,
                    count: labVitalFileReplayRepeatMode == .count ? labVitalFileReplayCount : nil
                )
            )))
            if let sessionID = labSessionResponse.session?.sessionId {
                applyLabSessionResponse(try await controlClient.startLabSession(sessionId: sessionID))
            }
            await refreshProductLabReadModels()
            await refreshVitalRecorders()
            recordLabSessionResult(RuntimeLabPanelText.replayedLabVitalFile)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    func uploadVitalFileToProductLab() async {
        guard !labVitalFileUploadSources.isEmpty else {
            recordLabActionMessage(RuntimeLabPanelText.chooseVitalFilesForUpload, tone: .failure)
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }

        recordLabActionMessage(RuntimeLabPanelText.uploadingLabVitalFiles)
        message = RuntimeLabPanelText.uploadingLabVitalFiles
        do {
            let sources = try nativeShell.readVitalFileUploadSources(
                labVitalFileUploadSources
            )
            let response = try await controlClient.uploadLabVitalFiles(sources)
            labVitalFileImportMessage = RuntimeLabPanelText.uploadedLabVitalFiles(
                response.files.count
            )
            labVitalFileUploadSources = []
            await refreshProductLabReadModels()
            recordLabActionMessage(labVitalFileImportMessage)
            message = labVitalFileImportMessage
        } catch {
            labVitalFileImportMessage = error.localizedDescription
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    func refreshProductLabReadModels() async {
        guard labCanUseProductLab else {
            return
        }

        do {
            applyLabSessions(try await controlClient.loadLabSessions())
            if !selectedLabSessionID.isEmpty {
                applyLabSessionResponse(
                    try await controlClient.loadLabSession(sessionId: selectedLabSessionID)
                )
            }
        } catch {
            labSessions = RuntimeLabSessionList.unavailable(readError: error.localizedDescription)
            labSessionResponse = RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription)
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }

        do {
            applyLabBeds(try await controlClient.loadLabBeds())
        } catch {
            labBeds = RuntimeLabBedList.unavailable(readError: error.localizedDescription)
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }

        do {
            applyLabRecorders(try await controlClient.loadLabRecorders())
        } catch {
            labRecorders = RuntimeLabRecorderList.unavailable(readError: error.localizedDescription)
            recordLabActionMessage(error.localizedDescription, tone: .failure)
        }

        do {
            applyLabVitalFiles(try await controlClient.loadLabVitalFiles())
        } catch {
            labVitalFiles = RuntimeLabVitalFileList.unavailable(readError: error.localizedDescription)
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
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
            await refreshVitalRecorders()
            recordLabSessionResult(successMessage)
        } catch {
            applyLabSessionResponse(RuntimeLabSessionResponse.unavailable(readError: error.localizedDescription))
            recordLabActionMessage(error.localizedDescription, tone: .failure)
            message = error.localizedDescription
        }
    }

    private func runProductLabRecorderCommand(recorderID: String, start: Bool) async {
        guard labCanUseProductLab, !isRunningLabAction else {
            recordLabActionMessage(RuntimeLabPanelText.labCapabilityUnavailable, tone: .failure)
            return
        }
        guard let session = selectedLabSession else {
            recordLabActionMessage(RuntimeLabPanelText.noLabSession, tone: .failure)
            return
        }
        guard let recorder = selectedLabSessionRecorders.first(where: { $0.recorderId == recorderID }) else {
            recordLabActionMessage(RuntimeLabPanelText.chooseSessionLabRecorder, tone: .failure)
            return
        }
        if start, session.state != .running {
            recordLabActionMessage(RuntimeLabPanelText.runningLabSessionRequired, tone: .failure)
            return
        }
        if !start, recorder.state != .running {
            recordLabActionMessage(RuntimeLabPanelText.labRecorderCommandFailed, tone: .failure)
            return
        }

        isRunningLabAction = true
        defer { isRunningLabAction = false }
        recordLabActionMessage(
            start ? RuntimeLabPanelText.startingLabRecorder : RuntimeLabPanelText.stoppingLabRecorder
        )
        do {
            let response = if start {
                try await controlClient.startLabRecorder(
                    sessionId: session.sessionId,
                    recorderId: recorderID
                )
            } else {
                try await controlClient.stopLabRecorder(
                    sessionId: session.sessionId,
                    recorderId: recorderID
                )
            }
            if response.state == .loaded, let recorder = response.recorder {
                recordLabActionMessage(
                    start
                        ? RuntimeLabPanelText.startedLabRecorder(recorder.vrcode)
                        : RuntimeLabPanelText.stoppedLabRecorder(recorder.vrcode)
                )
            } else {
                recordLabActionMessage(
                    response.readError ?? RuntimeLabPanelText.labRecorderCommandFailed,
                    tone: .failure
                )
            }
            applyLabRecorders(try await controlClient.loadLabRecorders())
            await refreshVitalRecorders()
        } catch {
            recordLabActionMessage(error.localizedDescription, tone: .failure)
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
        if selectedLabVitalFileRelativePath.isEmpty
            || !vitalFiles.vitalFiles.contains(where: { $0.relativePath == selectedLabVitalFileRelativePath })
        {
            selectedLabVitalFileRelativePath = vitalFiles.vitalFiles.first?.relativePath ?? ""
        }
    }

    private func applyLabSessionResponse(_ response: RuntimeLabSessionResponse) {
        labSessionResponse = response
        if let session = response.session {
            selectedLabSessionID = session.sessionId
        }
    }

    private func applyLabSessions(_ response: RuntimeLabSessionList) {
        labSessions = response
        guard response.state == .loaded else {
            return
        }
        guard selectedLabSessionID.isEmpty
            || !response.sessions.contains(where: { $0.sessionId == selectedLabSessionID })
        else {
            return
        }
        selectedLabSessionID = response.sessions.first(where: { $0.state == .running })?.sessionId
            ?? response.sessions.first?.sessionId
            ?? ""
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

    private func replayResourceSelection() -> RuntimeLabVitalFileReplayResourceSelection {
        if labVitalFileReplayResourceMode == .quickCreate {
            return RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate)
        }
        return RuntimeLabVitalFileReplayResourceSelection(
            mode: .existing,
            bedId: selectedLabBedID,
            recorderId: selectedLabRecorderID
        )
    }

    private func labSessionBedIDsList() -> [String] {
        labSessionBedIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
