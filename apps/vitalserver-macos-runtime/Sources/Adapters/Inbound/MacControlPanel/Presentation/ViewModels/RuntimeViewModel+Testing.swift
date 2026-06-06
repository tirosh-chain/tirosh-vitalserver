import Foundation
import RuntimeControl
import Errors

extension RuntimeViewModel {
    var testKitCanStart: Bool {
        testKitStatePolicy.canStart(
            controllerAvailable: testKitController != nil,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction,
            selectedBedRoomNames: selectedTestKitBedRoomNames,
            recorderCount: testKitRecorderCount
        )
    }

    var testKitCanStop: Bool {
        testKitStatePolicy.canStop(
            controllerAvailable: testKitController != nil,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction,
            selectedSessionID: selectedTestKitSessionID
        )
    }

    var testKitCanResetBeds: Bool {
        testKitStatePolicy.canResetBeds(
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction
        )
    }

    func testKitCanDeleteBed(_ roomName: String) -> Bool {
        testKitStatePolicy.canDeleteBed(
            roomName,
            status: testKitStatus,
            isRunningAction: isRunningTestKitAction
        )
    }

    var availableTestKitBedCount: Int {
        availableTestKitBedRoomNames.count
    }

    var selectedTestKitBedCount: Int {
        selectedAvailableTestKitBedRoomNames.count
    }

    var selectedTestKitSession: RuntimeTestKitSession? {
        testKitStatePolicy.selectedSession(
            status: testKitStatus,
            selectedSessionID: selectedTestKitSessionID
        )
    }

    func refreshTestKitStatus() async {
        guard let testKitController else {
            testKitStatus = RuntimeTestKitStatus(enabled: false, state: .disabled)
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        applyTestKitStatus(await testKitController.loadTestKitStatus())
    }

    func createTestKitBeds() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.creatingBeds
        message = RuntimeTestPanelText.creatingBeds
        do {
            let existingRoomNames = Set(testKitStatus.beds.map(\.roomName))
            let beds = try await testKitController.createTestKitBeds(RuntimeTestKitCreateBedsRequest(
                count: normalizedTestKitBedCount,
                prefix: normalizedTestKitBedPrefix
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            selectNewlyCreatedBeds(beds, existingRoomNames: existingRoomNames)
            let createdMessage = RuntimeTestPanelText.createdBeds(beds.count)
            testKitActionMessage = createdMessage
            message = createdMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func resetTestKitBeds() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        let bedCount = testKitStatus.beds.count
        guard activeTestKitBedRoomNames.isEmpty else {
            let errorMessage = RuntimeTestPanelText.stopSessionsBeforeResettingBeds
            testKitActionMessage = errorMessage
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.resettingBeds
        message = RuntimeTestPanelText.resettingBeds
        do {
            _ = try await testKitController.resetTestKitBeds()
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            selectedTestKitBedRoomNames.removeAll()
            let resetMessage = RuntimeTestPanelText.resetBeds(bedCount)
            testKitActionMessage = resetMessage
            message = resetMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func deleteTestKitBed(_ bed: RuntimeTestKitBed) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        guard !testKitBedIsActive(bed.roomName) else {
            let errorMessage = RuntimeTestPanelText.stopSessionsBeforeDeletingBed
            testKitActionMessage = errorMessage
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.deletingBed(bed.roomName)
        message = RuntimeTestPanelText.deletingBed(bed.roomName)
        do {
            _ = try await testKitController.deleteTestKitBeds(RuntimeTestKitDeleteBedsRequest(
                roomNames: [bed.roomName]
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            selectedTestKitBedRoomNames.remove(bed.roomName)
            let deletedMessage = RuntimeTestPanelText.deletedBed(bed.roomName)
            testKitActionMessage = deletedMessage
            message = deletedMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func startVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        guard selectedAvailableTestKitBedRoomNames.count >= normalizedTestKitRecorderCount else {
            let errorMessage = RuntimeTestPanelText.insufficientSelectedBeds(
                selectedAvailableTestKitBedRoomNames.count,
                normalizedTestKitRecorderCount
            )
            testKitActionMessage = errorMessage
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.startingSession
        message = RuntimeTestPanelText.startingSession
        do {
            let session = try await testKitController.startVirtualRecorders(testKitStartRequest())
            selectedTestKitSessionID = session.id
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            testKitVrcode = Self.generatedTestKitVrcode()
            let startedMessage = RuntimeTestPanelText.startedSession(session.id)
            testKitActionMessage = startedMessage
            message = startedMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
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
            successMessage: RuntimeTestPanelText.stoppedSession
        )
    }

    func restartVirtualRecorderSession(session: RuntimeTestKitSession) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        let requiredBeds = max(session.recordersRequested, 1)
        let bedRoomNames = Array(selectedAvailableTestKitBedRoomNames.prefix(requiredBeds))
        guard bedRoomNames.count >= requiredBeds else {
            let errorMessage = RuntimeTestPanelText.insufficientSelectedBeds(
                bedRoomNames.count,
                requiredBeds
            )
            testKitActionMessage = errorMessage
            message = errorMessage
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.restartingSession
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
            testKitActionMessage = restartedMessage
            message = restartedMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    private func runTestKitSessionAction(
        sessionID: String?,
        progressMessage: String,
        action: @MainActor (any RuntimeTestKitControlling, String?) async throws -> RuntimeTestKitSession?,
        successMessage: (String) -> String
    ) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = progressMessage
        message = progressMessage
        do {
            let session = try await action(testKitController, sessionID)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let actionMessage = session.map { successMessage($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            testKitActionMessage = actionMessage
            message = actionMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func deleteVirtualRecorderSession(sessionID: String?) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.deletingSession
        message = RuntimeTestPanelText.deletingSession
        do {
            let session = try await testKitController.deleteVirtualRecorders(sessionID: sessionID)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            let deletedMessage = session.map { RuntimeTestPanelText.deletedSession($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            testKitActionMessage = deletedMessage
            message = deletedMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func resetVirtualRecorderSessions() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        let sessionCount = testKitStatus.sessions.count
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.resettingSessions
        message = RuntimeTestPanelText.resettingSessions
        do {
            applyTestKitStatus(try await testKitController.resetVirtualRecorders())
            await refreshVitalRecorders()
            let resetMessage = RuntimeTestPanelText.resetSessions(sessionCount)
            testKitActionMessage = resetMessage
            message = resetMessage
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    func deleteOrphanVirtualRecorder() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        let vrcode = normalizedTestKitOrphanVrcode
        guard !vrcode.isEmpty else {
            testKitActionMessage = RuntimeTestPanelText.missingVrcode
            message = RuntimeTestPanelText.missingVrcode
            return
        }

        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.deletingVRecorder(vrcode)
        message = RuntimeTestPanelText.deletingVRecorder(vrcode)
        do {
            let deletion = try await testKitController.deleteVirtualRecorder(vrcode: vrcode)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            await refreshVitalRecorders()
            let deletionMessage = deletion.deleted
                ? RuntimeTestPanelText.deletedVRecorder(deletion.vrcode)
                : RuntimeTestPanelText.failedVRecorderDeletion(deletion.vrcode, deletion.error)
            testKitActionMessage = deletionMessage
            message = deletionMessage
            if deletion.deleted {
                testKitOrphanVrcode = ""
            }
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let errorMessage = error.localizedDescription
            testKitActionMessage = errorMessage
            message = errorMessage
        }
    }

    private func testKitStartRequest() -> RuntimeTestKitVirtualRecorderStartRequest {
        testKitStatePolicy.startRequest(RuntimeViewModelTestKitStartInput(
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
        testKitStatePolicy.normalizedRecorderCount(testKitRecorderCount)
    }

    private var normalizedTestKitBedCount: Int {
        testKitStatePolicy.normalizedBedCount(testKitBedCount)
    }

    private var normalizedTestKitBedPrefix: String {
        testKitStatePolicy.normalizedBedPrefix(testKitBedPrefix)
    }

    private var availableTestKitBedRoomNames: [String] {
        testKitStatePolicy.availableBedRoomNames(in: testKitStatus)
    }

    private var selectedAvailableTestKitBedRoomNames: [String] {
        testKitStatePolicy.selectedAvailableBedRoomNames(
            status: testKitStatus,
            selectedBedRoomNames: selectedTestKitBedRoomNames
        )
    }

    private var activeTestKitBedRoomNames: Set<String> {
        testKitStatePolicy.activeBedRoomNames(in: testKitStatus)
    }

    private var normalizedTestKitOrphanVrcode: String {
        testKitStatePolicy.normalizedRequiredVrcode(testKitOrphanVrcode)
    }

    static func generatedTestKitVrcode() -> String {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .uppercased()
        return "VR_\(suffix)"
    }

    private func applyTestKitStatus(_ status: RuntimeTestKitStatus) {
        testKitStatus = status
        pruneSelectedTestKitBeds(status)
        guard !status.sessions.isEmpty else {
            selectedTestKitSessionID = ""
            return
        }
        if selectedTestKitSessionID.isEmpty
            || !status.sessions.contains(where: { $0.id == selectedTestKitSessionID }) {
            selectedTestKitSessionID = status.activeSession?.id ?? status.sessions[0].id
        }
    }

    private func selectNewlyCreatedBeds(_ beds: [RuntimeTestKitBed], existingRoomNames: Set<String>) {
        let availableRoomNames = Set(availableTestKitBedRoomNames)
        for roomName in beds.map(\.roomName) where !existingRoomNames.contains(roomName) && availableRoomNames.contains(roomName) {
            selectedTestKitBedRoomNames.insert(roomName)
        }
    }

    private func pruneSelectedTestKitBeds(_ status: RuntimeTestKitStatus) {
        selectedTestKitBedRoomNames = selectedTestKitBedRoomNames.intersection(
            Set(testKitStatePolicy.availableBedRoomNames(in: status))
        )
    }
}
