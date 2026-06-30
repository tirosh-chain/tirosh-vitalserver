import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeTestKitPresentationPolicyTests: XCTestCase {
    private let policy = RuntimeTestKitPresentationPolicy()

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

        let request = policy.startRequest(RuntimeTestKitStartInput(
            status: status,
            selectedBedRoomNames: ["OR-A", "OR-B", "OR-C"],
            scenario: .signalArtifact,
            recorderCount: 2,
            vrcode: "  VR_123  ",
            intervalSeconds: 0.01,
            durationSeconds: 100_000,
            maxMessages: 2_000_000,
            shiftTime: false,
            generateFrames: false
        ))

        XCTAssertEqual(request.bedroomName, "OR-B")
        XCTAssertEqual(request.recorders, 2)
        XCTAssertEqual(request.vrcode, "VR_123")
        XCTAssertEqual(request.intervalSeconds, 0.1)
        XCTAssertEqual(request.window?.durationSeconds, 86_400)
        XCTAssertEqual(request.maxMessages, 1_000_000)
        XCTAssertFalse(request.shiftTime)
        XCTAssertFalse(request.generateFrames)
        XCTAssertTrue(request.output.exportVital)
        XCTAssertTrue(request.output.uploadVital)
        XCTAssertEqual(request.output.vitalUploadEndpoint, "/upload")
    }

    func testSelectionStateKeepsValidSessionAndPrunesUnavailableBeds() {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            activeSession: testKitSession(id: "active", state: "running", bedRoomNames: ["OR-A"]),
            sessions: [
                testKitSession(id: "active", state: "running", bedRoomNames: ["OR-A"]),
                testKitSession(id: "selected", state: "running", bedRoomNames: ["OR-B"]),
            ],
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
                RuntimeTestKitBed(roomName: "OR-C", bedID: "bed-c"),
            ]
        )

        let selection = policy.selectionState(
            status: status,
            selectedSessionID: "selected",
            selectedBedRoomNames: ["OR-A", "OR-C"]
        )

        XCTAssertEqual(selection.selectedSessionID, "selected")
        XCTAssertEqual(selection.selectedBedRoomNames, ["OR-C"])
    }

    func testSelectionStateFallsBackToActiveSessionAndClearsWhenNoSessionsRemain() {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            activeSession: testKitSession(id: "active", state: "running", bedRoomNames: []),
            sessions: [
                testKitSession(id: "active", state: "running", bedRoomNames: []),
            ],
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
            ]
        )

        XCTAssertEqual(
            policy.selectionState(
                status: status,
                selectedSessionID: "missing",
                selectedBedRoomNames: ["OR-A"]
            ),
            RuntimeTestKitSelectionState(selectedSessionID: "active", selectedBedRoomNames: ["OR-A"])
        )
        XCTAssertEqual(
            policy.selectionState(
                status: RuntimeTestKitStatus(enabled: true, state: .running),
                selectedSessionID: "active",
                selectedBedRoomNames: ["OR-A"]
            ),
            RuntimeTestKitSelectionState(selectedSessionID: "", selectedBedRoomNames: [])
        )
    }

    func testSessionControlStateIsTheOnlyPresentationStateInterpreter() {
        XCTAssertEqual(
            policy.sessionControlState(testKitSession(id: "running", state: " running ", bedRoomNames: [])),
            .running
        )
        XCTAssertEqual(
            policy.sessionControlState(testKitSession(id: "paused", state: "PAUSED", bedRoomNames: [])),
            .paused
        )
        XCTAssertEqual(
            policy.sessionControlState(testKitSession(id: "stopped", state: "stopped", bedRoomNames: [])),
            .terminal
        )
        XCTAssertEqual(
            policy.sessionControlState(testKitSession(id: "failed", state: "failed", bedRoomNames: [])),
            .terminal
        )
        XCTAssertEqual(
            policy.sessionControlState(testKitSession(id: "unknown", state: "booting", bedRoomNames: [])),
            .unavailable
        )
    }

    func testSessionRestartRequiresTerminalStateAndEnoughSelectedBeds() {
        let stopped = testKitSession(
            id: "stopped",
            state: "stopped",
            recordersRequested: 2,
            bedRoomNames: []
        )
        let running = testKitSession(
            id: "running",
            state: "running",
            recordersRequested: 1,
            bedRoomNames: []
        )

        XCTAssertEqual(policy.restartRequiredBedCount(stopped), 2)
        XCTAssertFalse(policy.sessionIsRestartable(stopped, selectedBedCount: 1))
        XCTAssertTrue(policy.sessionIsRestartable(stopped, selectedBedCount: 2))
        XCTAssertFalse(policy.sessionIsRestartable(running, selectedBedCount: 2))
    }

    func testNormalizationHelpersClampOperatorInputs() {
        XCTAssertEqual(policy.normalizedRecorderCount(0), 1)
        XCTAssertEqual(policy.normalizedRecorderCount(300), 200)
        XCTAssertEqual(policy.normalizedBedCount(0), 1)
        XCTAssertEqual(policy.normalizedBedCount(300), 200)
        XCTAssertEqual(policy.normalizedBedPrefix("  "), "testbed")
        XCTAssertEqual(policy.normalizedBedPrefix("  icu  "), "icu")
        XCTAssertNil(policy.normalizedVrcode("  "))
        XCTAssertEqual(policy.normalizedRequiredVrcode("  VR_X  "), "VR_X")
        XCTAssertNil(policy.normalizedSessionID(nil))
        XCTAssertNil(policy.normalizedSessionID("   "))
        XCTAssertEqual(policy.normalizedSessionID("  session-1  "), "session-1")
    }
}

private func testKitSession(
    id: String,
    state: String,
    recordersRequested: Int? = nil,
    bedRoomNames: [String]
) -> RuntimeTestKitSession {
    RuntimeTestKitSession(
        id: id,
        state: state,
        targetURL: "http://example.test",
        recordersRequested: recordersRequested ?? max(bedRoomNames.count, 1),
        bedsRequested: 1,
        bedroomName: bedRoomNames.first ?? "TestBedroom",
        vrcode: nil,
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: nil,
        maxMessages: nil,
        shiftTime: true,
        generateFrames: true,
        scenario: "normal_monitoring",
        createdAt: nil,
        startedAt: nil,
        stoppedAt: nil,
        messagesSent: 0,
        bytesSent: 0,
        lastError: nil,
        recorders: []
    )
}
