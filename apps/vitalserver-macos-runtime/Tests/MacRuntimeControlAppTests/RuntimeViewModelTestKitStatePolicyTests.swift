import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeViewModelTestKitStatePolicyTests: XCTestCase {
    private let policy = RuntimeViewModelTestKitStatePolicy()

    func testCanStartRequiresControllerEnabledIdleAndEnoughSelectedAvailableBeds() {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            sessions: [
                testKitSession(
                    id: "session-a",
                    state: "running",
                    bedRoomNames: ["OR-A"]
                ),
            ],
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
            ]
        )

        XCTAssertFalse(policy.canStart(
            controllerAvailable: true,
            status: status,
            isRunningAction: false,
            selectedBedRoomNames: ["OR-A"],
            recorderCount: 1
        ))
        XCTAssertTrue(policy.canStart(
            controllerAvailable: true,
            status: status,
            isRunningAction: false,
            selectedBedRoomNames: ["OR-B"],
            recorderCount: 1
        ))
        XCTAssertFalse(policy.canStart(
            controllerAvailable: false,
            status: status,
            isRunningAction: false,
            selectedBedRoomNames: ["OR-B"],
            recorderCount: 1
        ))
    }

    func testSelectedSessionAndStopCapabilityIgnoreTerminalSessions() {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            activeSession: testKitSession(id: "active", state: "running", bedRoomNames: []),
            sessions: [
                testKitSession(id: "stopped", state: "stopped", bedRoomNames: []),
                testKitSession(id: "running", state: "running", bedRoomNames: []),
            ]
        )

        XCTAssertEqual(policy.selectedSession(status: status, selectedSessionID: "").map(\.id), "active")
        XCTAssertFalse(policy.selectedSessionIsStoppable(status: status, selectedSessionID: "stopped"))
        XCTAssertTrue(policy.selectedSessionIsStoppable(status: status, selectedSessionID: "running"))
    }

    func testStartRequestUsesNormalizedInputsAndSelectedAvailableBeds() {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            sessions: [
                testKitSession(id: "session-a", state: "running", bedRoomNames: ["OR-A"]),
            ],
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
                RuntimeTestKitBed(roomName: "OR-C", bedID: "bed-c"),
            ]
        )

        let request = policy.startRequest(RuntimeViewModelTestKitStartInput(
            status: status,
            selectedBedRoomNames: ["OR-A", "OR-B", "OR-C"],
            scenario: .burstTraffic,
            signalProfile: .artifact,
            recorderCount: 2,
            vrcode: "  VR_123  ",
            intervalSeconds: 0.01,
            durationSeconds: 100_000,
            maxMessages: 2_000_000,
            shiftTime: false,
            generateFrames: false
        ))

        XCTAssertEqual(request.bedRoomNames, ["OR-B", "OR-C"])
        XCTAssertEqual(request.recorders, 2)
        XCTAssertEqual(request.vrcode, "VR_123")
        XCTAssertEqual(request.intervalSeconds, 0.1)
        XCTAssertEqual(request.durationSeconds, 86_400)
        XCTAssertEqual(request.maxMessages, 1_000_000)
        XCTAssertFalse(request.shiftTime)
        XCTAssertFalse(request.generateFrames)
    }

    func testNormalizationHelpersClampOperatorInputs() {
        XCTAssertEqual(policy.normalizedRecorderCount(0), 1)
        XCTAssertEqual(policy.normalizedRecorderCount(300), 200)
        XCTAssertEqual(policy.normalizedBedCount(0), 1)
        XCTAssertEqual(policy.normalizedBedCount(300), 200)
        XCTAssertEqual(policy.normalizedBedPrefix("  "), "testkit-bed")
        XCTAssertEqual(policy.normalizedBedPrefix("  icu  "), "icu")
        XCTAssertNil(policy.normalizedVrcode("  "))
        XCTAssertEqual(policy.normalizedRequiredVrcode("  VR_X  "), "VR_X")
    }
}

private func testKitSession(
    id: String,
    state: String,
    bedRoomNames: [String]
) -> RuntimeTestKitSession {
    RuntimeTestKitSession(
        id: id,
        state: state,
        targetURL: "http://example.test",
        recordersRequested: max(bedRoomNames.count, 1),
        bedsRequested: bedRoomNames.count,
        bedRoomNames: bedRoomNames,
        vrcode: nil,
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: nil,
        maxMessages: nil,
        shiftTime: true,
        generateFrames: true,
        defaultScenario: "normal",
        createdAt: nil,
        startedAt: nil,
        stoppedAt: nil,
        messagesSent: 0,
        bytesSent: 0,
        lastError: nil,
        recorders: []
    )
}
