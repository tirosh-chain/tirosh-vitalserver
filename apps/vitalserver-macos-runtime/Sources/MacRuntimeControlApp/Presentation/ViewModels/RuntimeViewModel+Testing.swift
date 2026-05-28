import Foundation
import RuntimeControl

extension RuntimeViewModel {
    var testKitCanStart: Bool {
        testKitController != nil
            && testKitStatus.enabled
            && !isRunningTestKitAction
            && testKitStatus.state != .starting
            && testKitStatus.state != .stopping
            && availableTestKitBedRoomNames.count >= normalizedTestKitRecorderCount
    }

    var testKitCanStop: Bool {
        testKitController != nil
            && testKitStatus.enabled
            && !isRunningTestKitAction
            && selectedTestKitSessionIsStoppable
    }

    var testKitCanResetBeds: Bool {
        testKitStatus.enabled
            && !isRunningTestKitAction
            && !testKitStatus.beds.isEmpty
            && activeTestKitBedRoomNames.isEmpty
    }

    var selectedTestKitSession: RuntimeTestKitSession? {
        if !selectedTestKitSessionID.isEmpty,
           let selected = testKitStatus.sessions.first(where: { $0.id == selectedTestKitSessionID }) {
            return selected
        }
        return testKitStatus.activeSession
    }

    private var selectedTestKitSessionIsStoppable: Bool {
        guard let selectedTestKitSession else {
            return false
        }
        return !["stopped", "failed"].contains(selectedTestKitSession.state.lowercased())
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
            let beds = try await testKitController.createTestKitBeds(RuntimeTestKitCreateBedsRequest(
                count: normalizedTestKitBedCount,
                prefix: normalizedTestKitBedPrefix
            ))
            applyTestKitStatus(await testKitController.loadTestKitStatus())
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

    func startVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        guard availableTestKitBedRoomNames.count >= normalizedTestKitRecorderCount else {
            let errorMessage = RuntimeTestPanelText.insufficientBeds(
                availableTestKitBedRoomNames.count,
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

    func stopVirtualRecorderSession() async {
        await stopVirtualRecorderSession(sessionID: selectedTestKitSession?.id)
    }

    func stopVirtualRecorderSession(sessionID: String?) async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        testKitActionMessage = RuntimeTestPanelText.stoppingSession
        message = RuntimeTestPanelText.stoppingSession
        do {
            let session = try await testKitController.stopVirtualRecorders(sessionID: sessionID)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            let stoppedMessage = session.map { RuntimeTestPanelText.stoppedSession($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
            testKitActionMessage = stoppedMessage
            message = stoppedMessage
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
        RuntimeTestKitVirtualRecorderStartRequest(
            targetURL: AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort),
            scenario: testKitScenario,
            signalProfile: testKitSignalProfile,
            recorders: normalizedTestKitRecorderCount,
            bedRoomNames: Array(availableTestKitBedRoomNames.prefix(normalizedTestKitRecorderCount)),
            vrcode: normalizedTestKitVrcode,
            version: "testkit",
            intervalSeconds: normalizedTestKitIntervalSeconds,
            durationSeconds: normalizedTestKitDurationSeconds,
            maxMessages: normalizedTestKitMaxMessages,
            shiftTime: testKitShiftTime,
            generateFrames: testKitGenerateFrames
        )
    }

    private var normalizedTestKitRecorderCount: Int {
        min(max(testKitRecorderCount, 1), 200)
    }

    private var normalizedTestKitBedCount: Int {
        min(max(testKitBedCount, 1), 200)
    }

    private var normalizedTestKitBedPrefix: String {
        let trimmed = testKitBedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "testkit-bed" : trimmed
    }

    private var availableTestKitBedRoomNames: [String] {
        let activeRoomNames = activeTestKitBedRoomNames
        return testKitStatus.beds
            .map(\.roomName)
            .filter { !activeRoomNames.contains($0) }
    }

    private var activeTestKitBedRoomNames: Set<String> {
        Set(
            testKitStatus.sessions
                .filter { !["stopped", "failed"].contains($0.state.lowercased()) }
                .flatMap(\.bedRoomNames)
        )
    }

    private var normalizedTestKitIntervalSeconds: Double {
        min(max(testKitIntervalSeconds, 0.1), 60)
    }

    private var normalizedTestKitDurationSeconds: Double? {
        testKitDurationSeconds > 0 ? min(testKitDurationSeconds, 86_400) : nil
    }

    private var normalizedTestKitMaxMessages: Int? {
        testKitMaxMessages > 0 ? min(testKitMaxMessages, 1_000_000) : nil
    }

    private var normalizedTestKitVrcode: String? {
        let trimmed = testKitVrcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedTestKitOrphanVrcode: String {
        testKitOrphanVrcode.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard !status.sessions.isEmpty else {
            selectedTestKitSessionID = ""
            return
        }
        if selectedTestKitSessionID.isEmpty
            || !status.sessions.contains(where: { $0.id == selectedTestKitSessionID }) {
            selectedTestKitSessionID = status.activeSession?.id ?? status.sessions[0].id
        }
    }
}
