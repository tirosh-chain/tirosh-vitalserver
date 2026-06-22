import Foundation
import RuntimeControl
import Errors

extension RuntimeViewModel {
    var testKitCanStart: Bool {
        testKitPresentationPolicy.canStart(
            controllerAvailable: testKitController != nil,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction,
            selectedBedRoomNames: selectedTestKitBedRoomNames,
            recorderCount: testKitRecorderCount
        )
    }

    var testKitCanStop: Bool {
        testKitPresentationPolicy.canStop(
            controllerAvailable: testKitController != nil,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction,
            selectedSessionID: selectedTestKitSessionID
        )
    }

    var testKitCanResetBeds: Bool {
        testKitPresentationPolicy.canResetBeds(
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction
        )
    }

    func testKitCanDeleteBed(_ roomName: String) -> Bool {
        testKitPresentationPolicy.canDeleteBed(
            roomName,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction
        )
    }

    func testKitSessionControlState(_ session: RuntimeTestKitSession) -> RuntimeTestKitSessionControlState {
        testKitPresentationPolicy.sessionControlState(session)
    }

    func testKitSessionIsRestartable(_ session: RuntimeTestKitSession) -> Bool {
        testKitPresentationPolicy.sessionIsRestartable(
            session,
            selectedBedCount: selectedTestKitBedCount
        )
    }

    func testKitRestartRequiredBedCount(_ session: RuntimeTestKitSession) -> Int {
        testKitPresentationPolicy.restartRequiredBedCount(session)
    }

    var availableTestKitBedCount: Int {
        availableTestKitBedRoomNames.count
    }

    var selectedTestKitBedCount: Int {
        selectedAvailableTestKitBedRoomNames.count
    }

    var selectedTestKitSession: RuntimeTestKitSession? {
        testKitPresentationPolicy.selectedSession(
            status: testKitStatus,
            selectedSessionID: selectedTestKitSessionID
        )
    }

    func recordTestKitActionMessage(
        _ value: String,
        tone: RuntimeTestKitActionMessageTone = .neutral
    ) {
        testKitActionMessage = value
        testKitActionMessageTone = tone
    }

    func refreshTestKitStatus() async {
        guard let testKitController else {
            testKitStatus = RuntimeTestKitStatus(enabled: false, state: .disabled)
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        applyTestKitStatus(await testKitController.loadTestKitStatus())
    }

    func createTestKitBeds() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.creatingBeds)
        message = RuntimeTestPanelText.creatingBeds
        do {
            let existingRoomNames = Set(testKitStatus.beds.map(\.roomName))
            let beds = try await testKitController.createTestKitBeds(RuntimeTestKitCreateBedsRequest(
                count: normalizedTestKitBedCount,
                prefix: normalizedTestKitBedPrefix,
                appendRandomSuffix: testKitAppendRandomBedSuffix
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            selectNewlyCreatedBeds(beds, existingRoomNames: existingRoomNames)
            let createdMessage = RuntimeTestPanelText.createdBeds(beds.count)
            recordTestKitActionMessage(createdMessage)
            message = createdMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func resetTestKitBeds() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        let bedCount = testKitStatus.beds.count
        guard activeTestKitBedRoomNames.isEmpty else {
            let errorMessage = RuntimeTestPanelText.stopSessionsBeforeResettingBeds
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.resettingBeds)
        message = RuntimeTestPanelText.resettingBeds
        do {
            _ = try await testKitController.resetTestKitBeds()
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            selectedTestKitBedRoomNames.removeAll()
            let resetMessage = RuntimeTestPanelText.resetBeds(bedCount)
            recordTestKitActionMessage(resetMessage)
            message = resetMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func deleteTestKitBed(_ bed: RuntimeTestKitBed) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        guard !testKitBedIsActive(bed.roomName) else {
            let errorMessage = RuntimeTestPanelText.stopSessionsBeforeDeletingBed
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.deletingBed(bed.roomName))
        message = RuntimeTestPanelText.deletingBed(bed.roomName)
        do {
            _ = try await testKitController.deleteTestKitBeds(RuntimeTestKitDeleteBedsRequest(
                roomNames: [bed.roomName]
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            selectedTestKitBedRoomNames.remove(bed.roomName)
            let deletedMessage = RuntimeTestPanelText.deletedBed(bed.roomName)
            recordTestKitActionMessage(deletedMessage)
            message = deletedMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func startVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        guard selectedAvailableTestKitBedRoomNames.count >= normalizedTestKitRecorderCount else {
            let errorMessage = RuntimeTestPanelText.insufficientSelectedBeds(
                selectedAvailableTestKitBedRoomNames.count,
                normalizedTestKitRecorderCount
            )
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.startingSession)
        message = RuntimeTestPanelText.startingSession
        do {
            let session = try await testKitController.startVirtualRecorders(testKitStartRequest())
            selectedTestKitSessionID = session.id
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            testKitVrcode = Self.generatedTestKitVrcode()
            let startedMessage = RuntimeTestPanelText.startedSession(session.id)
            recordTestKitActionMessage(startedMessage)
            message = startedMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func testKitBedIsSelected(_ roomName: String) -> Bool {
        selectedTestKitBedRoomNames.contains(roomName)
    }

    func testKitBedIsActive(_ roomName: String) -> Bool {
        activeTestKitBedRoomNames.contains(roomName)
    }

    func setTestKitBedSelection(_ roomName: String, selected: Bool) {
        guard !testKitBedIsActive(roomName) else {
            selectedTestKitBedRoomNames.remove(roomName)
            return
        }
        if selected {
            selectedTestKitBedRoomNames.insert(roomName)
        } else {
            selectedTestKitBedRoomNames.remove(roomName)
        }
    }

    func stopVirtualRecorderSession() async {
        await stopVirtualRecorderSession(sessionID: selectedTestKitSession?.id)
    }

    func pauseVirtualRecorderSession(sessionID: String?) async {
        await runTestKitSessionAction(
            sessionID: sessionID,
            progressMessage: RuntimeTestPanelText.pausingSession,
            action: { try await $0.pauseVirtualRecorders(sessionID: $1) },
            successMessage: RuntimeTestPanelText.pausedSession
        )
    }

    func resumeVirtualRecorderSession(sessionID: String?) async {
        await runTestKitSessionAction(
            sessionID: sessionID,
            progressMessage: RuntimeTestPanelText.resumingSession,
            action: { try await $0.resumeVirtualRecorders(sessionID: $1) },
            successMessage: RuntimeTestPanelText.resumedSession
        )
    }

    func stopVirtualRecorderSession(sessionID: String?) async {
        await runTestKitSessionAction(
            sessionID: sessionID,
            progressMessage: RuntimeTestPanelText.stoppingSession,
            action: { try await $0.stopVirtualRecorders(sessionID: $1) },
            successMessage: RuntimeTestPanelText.stoppedSession,
            followSessionUntilTerminal: true
        )
    }

    func restartVirtualRecorderSession(session: RuntimeTestKitSession) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        let requiredBeds = max(session.recordersRequested, 1)
        let bedRoomNames = Array(selectedAvailableTestKitBedRoomNames.prefix(requiredBeds))
        guard bedRoomNames.count >= requiredBeds else {
            let errorMessage = RuntimeTestPanelText.insufficientSelectedBeds(
                bedRoomNames.count,
                requiredBeds
            )
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.restartingSession)
        message = RuntimeTestPanelText.restartingSession
        do {
            let restarted = try await testKitController.restartVirtualRecorders(
                sessionID: session.id,
                bedRoomNames: bedRoomNames
            )
            if let restarted {
                selectedTestKitSessionID = restarted.id
            }
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let restartedMessage = restarted.map { RuntimeTestPanelText.restartedSession($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            recordTestKitActionMessage(restartedMessage, tone: restarted == nil ? .failure : .neutral)
            message = restartedMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    private func runTestKitSessionAction(
        sessionID: String?,
        progressMessage: String,
        action: @MainActor (any RuntimeTestKitControlling, String) async throws -> RuntimeTestKitSession?,
        successMessage: (String) -> String,
        followSessionUntilTerminal: Bool = false
    ) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        guard let sessionID = testKitPresentationPolicy.normalizedSessionID(sessionID) else {
            message = RuntimeTestPanelText.noActiveSession
            recordTestKitActionMessage(RuntimeTestPanelText.noActiveSession, tone: .failure)
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(progressMessage)
        message = progressMessage
        do {
            let session = try await action(testKitController, sessionID)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            if followSessionUntilTerminal, session != nil {
                await refreshTestKitSessionUntilTerminal(sessionID: sessionID, controller: testKitController)
            }
            let actionMessage = session.map { successMessage($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            recordTestKitActionMessage(actionMessage, tone: session == nil ? .failure : .neutral)
            message = actionMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    private func refreshTestKitSessionUntilTerminal(
        sessionID: String,
        controller: any RuntimeTestKitControlling
    ) async {
        for _ in 0..<20 {
            let status = await controller.loadTestKitStatus()
            applyTestKitStatus(status)
            guard let session = status.sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            if RuntimeTestKitSessionStatePolicy.isTerminal(session.state) {
                return
            }
            if !testKitSessionVitalFinalizationIsPending(session) {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func testKitSessionVitalFinalizationIsPending(_ session: RuntimeTestKitSession) -> Bool {
        switch RuntimeTestKitSessionStatePolicy.normalizedState(session.state) {
        case "stopping", "finalizing-vital", "uploading":
            return true
        default:
            return false
        }
    }

    func deleteVirtualRecorderSession(sessionID: String?) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        guard let sessionID = testKitPresentationPolicy.normalizedSessionID(sessionID) else {
            message = RuntimeTestPanelText.noActiveSession
            recordTestKitActionMessage(RuntimeTestPanelText.noActiveSession, tone: .failure)
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.deletingSession)
        message = RuntimeTestPanelText.deletingSession
        do {
            let session = try await testKitController.deleteVirtualRecorders(sessionID: sessionID)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            let deletedMessage = session.map { RuntimeTestPanelText.deletedSession($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            recordTestKitActionMessage(deletedMessage, tone: session == nil ? .failure : .neutral)
            message = deletedMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func resetVirtualRecorderSessions() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        let sessionCount = testKitStatus.sessions.count
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.resettingSessions)
        message = RuntimeTestPanelText.resettingSessions
        do {
            applyTestKitStatus(try await testKitController.resetVirtualRecorders())
            await refreshVitalRecorders()
            let resetMessage = RuntimeTestPanelText.resetSessions(sessionCount)
            recordTestKitActionMessage(resetMessage)
            message = resetMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func deleteOrphanVirtualRecorder() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        let vrcode = normalizedTestKitOrphanVrcode
        guard !vrcode.isEmpty else {
            recordTestKitActionMessage(RuntimeTestPanelText.missingVrcode, tone: .failure)
            message = RuntimeTestPanelText.missingVrcode
            return
        }

        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.deletingVRecorder(vrcode))
        message = RuntimeTestPanelText.deletingVRecorder(vrcode)
        do {
            let deletion = try await testKitController.deleteVirtualRecorder(vrcode: vrcode)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            let deletionMessage = deletion.deleted
                ? RuntimeTestPanelText.deletedVRecorder(deletion.vrcode)
                : RuntimeTestPanelText.failedVRecorderDeletion(deletion.vrcode, deletion.error)
            recordTestKitActionMessage(deletionMessage, tone: deletion.deleted ? .neutral : .failure)
            message = deletionMessage
            if deletion.deleted {
                testKitOrphanVrcode = ""
            }
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    func uploadVitalFilesFromTestTab() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            recordTestKitActionMessage(RuntimeTestPanelText.testKitUnavailable, tone: .failure)
            return
        }
        guard let uploader = testKitController as? any RuntimeTestKitVitalFileUploading else {
            let errorMessage = RuntimeTestKitVitalFileUploadError.uploadNotAvailable.localizedDescription
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }
        guard let proxyPort = status.proxyPort else {
            let errorMessage = RuntimeTestKitVitalFileUploadError.missingProxyPort.localizedDescription
            recordTestKitActionMessage(errorMessage, tone: .failure)
            message = errorMessage
            return
        }

        let selectedFiles = nativeShell.chooseVitalFiles(prompt: RuntimeTestPanelText.choosingVitalFiles)
        guard !selectedFiles.isEmpty else {
            return
        }

        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        recordTestKitActionMessage(RuntimeTestPanelText.uploadingVitalFiles)
        message = RuntimeTestPanelText.uploadingVitalFiles
        do {
            let summary = try await uploader.uploadVitalFiles(RuntimeTestKitVitalFileUploadRequest(
                filePaths: selectedFiles.map(\.path),
                vitalServerBaseURL: AppConstants.Product.vitalServerURL(proxyPort: proxyPort),
                endpoint: "/upload",
                registerBeds: true
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let summaryMessage = RuntimeTestPanelText.uploadedVitalFiles(summary)
            recordTestKitActionMessage(summaryMessage, tone: summary.failedCount > 0 ? .failure : .neutral)
            message = summaryMessage
        } catch {
            await applyTestKitActionFailure(error, controller: testKitController)
        }
    }

    private func testKitStartRequest() -> RuntimeTestKitVirtualRecorderStartRequest {
        testKitPresentationPolicy.startRequest(RuntimeTestKitStartInput(
            status: testKitStatus,
            selectedBedRoomNames: selectedTestKitBedRoomNames,
            scenario: testKitScenario,
            signalProfile: testKitSignalProfile,
            recorderCount: testKitRecorderCount,
            vrcode: testKitVrcode,
            intervalSeconds: testKitIntervalSeconds,
            durationSeconds: testKitDurationSeconds,
            maxMessages: testKitMaxMessages,
            shiftTime: testKitShiftTime,
            generateFrames: testKitGenerateFrames
        ))
    }

    private var normalizedTestKitRecorderCount: Int {
        testKitPresentationPolicy.normalizedRecorderCount(testKitRecorderCount)
    }

    private var normalizedTestKitBedCount: Int {
        guard testKitAppendRandomBedSuffix else {
            return 1
        }
        return testKitPresentationPolicy.normalizedBedCount(testKitBedCount)
    }

    private var normalizedTestKitBedPrefix: String {
        testKitPresentationPolicy.normalizedBedPrefix(testKitBedPrefix)
    }

    private var availableTestKitBedRoomNames: [String] {
        testKitPresentationPolicy.availableBedRoomNames(in: testKitStatus)
    }

    private var selectedAvailableTestKitBedRoomNames: [String] {
        testKitPresentationPolicy.selectedAvailableBedRoomNames(
            status: testKitStatus,
            selectedBedRoomNames: selectedTestKitBedRoomNames
        )
    }

    private var activeTestKitBedRoomNames: Set<String> {
        testKitPresentationPolicy.activeBedRoomNames(in: testKitStatus)
    }

    private var normalizedTestKitOrphanVrcode: String {
        testKitPresentationPolicy.normalizedRequiredVrcode(testKitOrphanVrcode)
    }

    static func generatedTestKitVrcode() -> String {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .uppercased()
        return "VR_\(suffix)"
    }

    private func applyTestKitStatus(_ status: RuntimeTestKitStatus) {
        let selection = testKitPresentationPolicy.selectionState(
            status: status,
            selectedSessionID: selectedTestKitSessionID,
            selectedBedRoomNames: selectedTestKitBedRoomNames
        )
        testKitStatus = status
        selectedTestKitSessionID = selection.selectedSessionID
        selectedTestKitBedRoomNames = selection.selectedBedRoomNames
    }

    private func applyTestKitActionFailure(
        _ error: Error,
        controller: any RuntimeTestKitControlling
    ) async {
        applyTestKitStatus(await controller.loadTestKitStatus())
        let errorMessage = error.localizedDescription
        recordTestKitActionMessage(errorMessage, tone: .failure)
        message = errorMessage
    }

    private func selectNewlyCreatedBeds(_ beds: [RuntimeTestKitBed], existingRoomNames: Set<String>) {
        let availableRoomNames = Set(availableTestKitBedRoomNames)
        for roomName in beds.map(\.roomName) where !existingRoomNames.contains(roomName) && availableRoomNames.contains(roomName) {
            selectedTestKitBedRoomNames.insert(roomName)
        }
    }

}
