import Foundation
import RuntimeControl

extension RuntimeViewModel {
    var testKitCanStart: Bool {
        testKitController != nil
            && testKitStatus.enabled
            && !isRunningTestKitAction
            && testKitStatus.state != .starting
            && testKitStatus.state != .stopping
    }

    var testKitCanStop: Bool {
        testKitController != nil
            && testKitStatus.enabled
            && !isRunningTestKitAction
            && selectedTestKitSessionIsStoppable
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

    func startVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            testKitActionMessage = RuntimeTestPanelText.testKitUnavailable
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

    private func testKitStartRequest() -> RuntimeTestKitVirtualRecorderStartRequest {
        RuntimeTestKitVirtualRecorderStartRequest(
            targetURL: AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort),
            scenario: testKitScenario,
            signalProfile: testKitSignalProfile,
            recorders: 1,
            vrcode: normalizedTestKitVrcode,
            version: "testkit",
            intervalSeconds: 1,
            shiftTime: true,
            generateFrames: true
        )
    }

    private var normalizedTestKitVrcode: String? {
        let trimmed = testKitVrcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
