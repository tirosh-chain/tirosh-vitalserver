import Foundation
import RuntimeControl
import Errors

public struct RuntimeTestKitStartInput {
    public let status: RuntimeTestKitStatus
    public let selectedBedRoomNames: Set<String>
    public let scenario: RuntimeTestKitScenario
    public let signalProfile: RuntimeTestKitSignalProfile
    public let recorderCount: Int
    public let vrcode: String
    public let intervalSeconds: Double
    public let durationSeconds: Double
    public let maxMessages: Int
    public let shiftTime: Bool
    public let generateFrames: Bool

    public init(
        status: RuntimeTestKitStatus,
        selectedBedRoomNames: Set<String>,
        scenario: RuntimeTestKitScenario,
        signalProfile: RuntimeTestKitSignalProfile,
        recorderCount: Int,
        vrcode: String,
        intervalSeconds: Double,
        durationSeconds: Double,
        maxMessages: Int,
        shiftTime: Bool,
        generateFrames: Bool
    ) {
        self.status = status
        self.selectedBedRoomNames = selectedBedRoomNames
        self.scenario = scenario
        self.signalProfile = signalProfile
        self.recorderCount = recorderCount
        self.vrcode = vrcode
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.maxMessages = maxMessages
        self.shiftTime = shiftTime
        self.generateFrames = generateFrames
    }
}

public struct RuntimeTestKitSelectionState: Equatable {
    public let selectedSessionID: String
    public let selectedBedRoomNames: Set<String>

    public init(selectedSessionID: String, selectedBedRoomNames: Set<String>) {
        self.selectedSessionID = selectedSessionID
        self.selectedBedRoomNames = selectedBedRoomNames
    }
}

public enum RuntimeTestKitSessionControlState: Equatable, Sendable {
    case running
    case paused
    case terminal
    case unavailable
}

public enum RuntimeTestKitActionMessageTone: Equatable, Sendable {
    case neutral
    case failure
}

public struct RuntimeTestKitPresentationPolicy {
    public init() {}

    public func canStart(
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
            && selectedAvailableBedRoomNames(
                status: status,
                selectedBedRoomNames: selectedBedRoomNames
            ).count >= normalizedRecorderCount(recorderCount)
    }

    public func canStop(
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

    public func canResetBeds(status: RuntimeTestKitStatus, isRunningAction: Bool) -> Bool {
        status.enabled
            && !isRunningAction
            && !status.beds.isEmpty
            && activeBedRoomNames(in: status).isEmpty
    }

    public func canDeleteBed(
        _ roomName: String,
        status: RuntimeTestKitStatus,
        isRunningAction: Bool
    ) -> Bool {
        status.enabled
            && !isRunningAction
            && !activeBedRoomNames(in: status).contains(roomName)
    }

    public func selectedSession(
        status: RuntimeTestKitStatus,
        selectedSessionID: String
    ) -> RuntimeTestKitSession? {
        if !selectedSessionID.isEmpty,
           let selected = status.sessions.first(where: { $0.id == selectedSessionID }) {
            return selected
        }
        return status.activeSession
    }

    public func selectedSessionIsStoppable(
        status: RuntimeTestKitStatus,
        selectedSessionID: String
    ) -> Bool {
        guard let selectedSession = selectedSession(status: status, selectedSessionID: selectedSessionID) else {
            return false
        }
        return !isTerminalSessionState(selectedSession.state)
    }

    public func sessionControlState(_ session: RuntimeTestKitSession) -> RuntimeTestKitSessionControlState {
        switch RuntimeTestKitSessionStatePolicy.normalizedState(session.state) {
        case "running":
            return .running
        case "paused":
            return .paused
        case "stopped", "failed", "vital-ready", "uploaded", "upload-failed":
            return .terminal
        default:
            return .unavailable
        }
    }

    public func sessionIsRestartable(
        _ session: RuntimeTestKitSession,
        selectedBedCount: Int
    ) -> Bool {
        sessionControlState(session) == .terminal
            && selectedBedCount >= restartRequiredBedCount(session)
    }

    public func restartRequiredBedCount(_ session: RuntimeTestKitSession) -> Int {
        max(session.recordersRequested, 1)
    }

    public func activeBedRoomNames(in status: RuntimeTestKitStatus) -> Set<String> {
        Set(
            status.sessions
                .filter { !isTerminalSessionState($0.state) }
                .flatMap(\.bedRoomNames)
        )
    }

    public func availableBedRoomNames(in status: RuntimeTestKitStatus) -> [String] {
        let activeRoomNames = activeBedRoomNames(in: status)
        return status.beds
            .map(\.roomName)
            .filter { !activeRoomNames.contains($0) }
    }

    public func selectedAvailableBedRoomNames(
        status: RuntimeTestKitStatus,
        selectedBedRoomNames: Set<String>
    ) -> [String] {
        availableBedRoomNames(in: status).filter { selectedBedRoomNames.contains($0) }
    }

    public func selectionState(
        status: RuntimeTestKitStatus,
        selectedSessionID: String,
        selectedBedRoomNames: Set<String>
    ) -> RuntimeTestKitSelectionState {
        RuntimeTestKitSelectionState(
            selectedSessionID: selectedSessionIDAfterStatusRefresh(
                status: status,
                selectedSessionID: selectedSessionID
            ),
            selectedBedRoomNames: selectedBedRoomNames.intersection(Set(availableBedRoomNames(in: status)))
        )
    }

    public func startRequest(
        _ input: RuntimeTestKitStartInput
    ) -> RuntimeTestKitVirtualRecorderStartRequest {
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
            generateFrames: input.generateFrames,
            exportVital: true,
            uploadVital: true,
            vitalUploadEndpoint: "/upload"
        )
    }

    public func normalizedRecorderCount(_ count: Int) -> Int {
        min(max(count, 1), 200)
    }

    public func normalizedBedCount(_ count: Int) -> Int {
        min(max(count, 1), 200)
    }

    public func normalizedBedPrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "testbed" : trimmed
    }

    public func normalizedIntervalSeconds(_ seconds: Double) -> Double {
        min(max(seconds, 0.1), 60)
    }

    public func normalizedDurationSeconds(_ seconds: Double) -> Double? {
        seconds > 0 ? min(seconds, 86_400) : nil
    }

    public func normalizedMaxMessages(_ count: Int) -> Int? {
        count > 0 ? min(count, 1_000_000) : nil
    }

    public func normalizedVrcode(_ vrcode: String) -> String? {
        let trimmed = vrcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func normalizedRequiredVrcode(_ vrcode: String) -> String {
        vrcode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func normalizedSessionID(_ sessionID: String?) -> String? {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func selectedSessionIDAfterStatusRefresh(
        status: RuntimeTestKitStatus,
        selectedSessionID: String
    ) -> String {
        guard !status.sessions.isEmpty else {
            return ""
        }
        if !selectedSessionID.isEmpty,
           status.sessions.contains(where: { $0.id == selectedSessionID }) {
            return selectedSessionID
        }
        return status.activeSession?.id ?? status.sessions[0].id
    }

    private func isTerminalSessionState(_ state: String) -> Bool {
        RuntimeTestKitSessionStatePolicy.isTerminal(state)
    }
}
