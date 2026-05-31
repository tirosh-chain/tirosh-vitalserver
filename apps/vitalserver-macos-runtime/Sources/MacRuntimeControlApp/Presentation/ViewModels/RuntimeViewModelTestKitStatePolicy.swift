import Foundation
import RuntimeControl

struct RuntimeViewModelTestKitStartInput {
    let status: RuntimeTestKitStatus
    let selectedBedRoomNames: Set<String>
    let scenario: RuntimeTestKitScenario
    let signalProfile: RuntimeTestKitSignalProfile
    let recorderCount: Int
    let vrcode: String
    let intervalSeconds: Double
    let durationSeconds: Double
    let maxMessages: Int
    let shiftTime: Bool
    let generateFrames: Bool
}

struct RuntimeViewModelTestKitStatePolicy {
    func canStart(
        controllerAvailable: Bool,
        status: RuntimeTestKitStatus,
        isRunningAction: Bool,
        selectedBedRoomNames: Set<String>,
        recorderCount: Int
    ) -> Bool {
        controllerAvailable
            && status.enabled
            && !isRunningAction
            && status.state != .starting
            && status.state != .stopping
            && selectedAvailableBedRoomNames(status: status, selectedBedRoomNames: selectedBedRoomNames).count >= normalizedRecorderCount(recorderCount)
    }

    func canStop(
        controllerAvailable: Bool,
        status: RuntimeTestKitStatus,
        isRunningAction: Bool,
        selectedSessionID: String
    ) -> Bool {
        controllerAvailable
            && status.enabled
            && !isRunningAction
            && selectedSessionIsStoppable(status: status, selectedSessionID: selectedSessionID)
    }

    func canResetBeds(status: RuntimeTestKitStatus, isRunningAction: Bool) -> Bool {
        status.enabled
            && !isRunningAction
            && !status.beds.isEmpty
            && activeBedRoomNames(in: status).isEmpty
    }

    func canDeleteBed(_ roomName: String, status: RuntimeTestKitStatus, isRunningAction: Bool) -> Bool {
        status.enabled
            && !isRunningAction
            && !activeBedRoomNames(in: status).contains(roomName)
    }

    func selectedSession(status: RuntimeTestKitStatus, selectedSessionID: String) -> RuntimeTestKitSession? {
        if !selectedSessionID.isEmpty,
           let selected = status.sessions.first(where: { $0.id == selectedSessionID }) {
            return selected
        }
        return status.activeSession
    }

    func selectedSessionIsStoppable(status: RuntimeTestKitStatus, selectedSessionID: String) -> Bool {
        guard let selectedSession = selectedSession(status: status, selectedSessionID: selectedSessionID) else {
            return false
        }
        return !isTerminalSessionState(selectedSession.state)
    }

    func activeBedRoomNames(in status: RuntimeTestKitStatus) -> Set<String> {
        Set(
            status.sessions
                .filter { !isTerminalSessionState($0.state) }
                .flatMap(\.bedRoomNames)
        )
    }

    func availableBedRoomNames(in status: RuntimeTestKitStatus) -> [String] {
        let activeRoomNames = activeBedRoomNames(in: status)
        return status.beds
            .map(\.roomName)
            .filter { !activeRoomNames.contains($0) }
    }

    func selectedAvailableBedRoomNames(
        status: RuntimeTestKitStatus,
        selectedBedRoomNames: Set<String>
    ) -> [String] {
        availableBedRoomNames(in: status).filter { selectedBedRoomNames.contains($0) }
    }

    func startRequest(_ input: RuntimeViewModelTestKitStartInput) -> RuntimeTestKitVirtualRecorderStartRequest {
        let recorderCount = normalizedRecorderCount(input.recorderCount)
        return RuntimeTestKitVirtualRecorderStartRequest(
            scenario: input.scenario,
            signalProfile: input.signalProfile,
            recorders: recorderCount,
            bedRoomNames: Array(selectedAvailableBedRoomNames(
                status: input.status,
                selectedBedRoomNames: input.selectedBedRoomNames
            ).prefix(recorderCount)),
            vrcode: normalizedVrcode(input.vrcode),
            version: "testkit",
            intervalSeconds: normalizedIntervalSeconds(input.intervalSeconds),
            durationSeconds: normalizedDurationSeconds(input.durationSeconds),
            maxMessages: normalizedMaxMessages(input.maxMessages),
            shiftTime: input.shiftTime,
            generateFrames: input.generateFrames
        )
    }

    func normalizedRecorderCount(_ count: Int) -> Int {
        min(max(count, 1), 200)
    }

    func normalizedBedCount(_ count: Int) -> Int {
        min(max(count, 1), 200)
    }

    func normalizedBedPrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "testkit-bed" : trimmed
    }

    func normalizedIntervalSeconds(_ seconds: Double) -> Double {
        min(max(seconds, 0.1), 60)
    }

    func normalizedDurationSeconds(_ seconds: Double) -> Double? {
        seconds > 0 ? min(seconds, 86_400) : nil
    }

    func normalizedMaxMessages(_ count: Int) -> Int? {
        count > 0 ? min(count, 1_000_000) : nil
    }

    func normalizedVrcode(_ vrcode: String) -> String? {
        let trimmed = vrcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedRequiredVrcode(_ vrcode: String) -> String {
        vrcode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTerminalSessionState(_ state: String) -> Bool {
        ["stopped", "failed"].contains(state.lowercased())
    }
}
