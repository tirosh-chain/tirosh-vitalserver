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
            return
        }
        applyTestKitStatus(await testKitController.loadTestKitStatus())
    }

    func startVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        do {
            let session = try await testKitController.startVirtualRecorders(testKitStartRequest())
            selectedTestKitSessionID = session.id
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            message = RuntimeTestPanelText.startedSession(session.id)
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            message = error.localizedDescription
        }
    }

    func stopVirtualRecorderSession() async {
        guard let testKitController else {
            message = RuntimeTestPanelText.testKitUnavailable
            return
        }
        isRunningTestKitAction = true
        defer { isRunningTestKitAction = false }

        do {
            let session = try await testKitController.stopVirtualRecorders(sessionID: selectedTestKitSession?.id)
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            message = session.map { RuntimeTestPanelText.stoppedSession($0.id) }
                ?? RuntimeTestPanelText.noActiveSession
        } catch {
            applyTestKitStatus(await testKitController.loadTestKitStatus())
            message = error.localizedDescription
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
