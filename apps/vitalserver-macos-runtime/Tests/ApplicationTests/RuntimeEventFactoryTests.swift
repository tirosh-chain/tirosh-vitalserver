import Contracts
import Application
import XCTest
import Errors

final class RuntimeEventFactoryTests: XCTestCase {
    func testObservedStatusEventCarriesHealthSnapshotContext() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 30
        )
        let snapshot = RuntimeHealthSnapshot(
            vmExecutable: .executable,
            proxyExecutable: .executable,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: [.missingIPAddress],
            vmIP: "192.168.64.2",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: observation,
            failureReasons: [.guestHTTP("503")]
        )

        let event = factory().observedStatusEvent(
            status: .degraded,
            previousStatus: .healthy,
            operation: .watchdog,
            message: "watchdog observed degraded runtime",
            healthSnapshot: snapshot,
            eventType: .domainErrorObserved
        )

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.timestamp, "2026-05-30T00:00:01Z")
        XCTAssertEqual(event.product, "VitalServerHelper")
        XCTAssertEqual(event.runtimeVersion, "1.2.3")
        XCTAssertEqual(event.status, .degraded)
        XCTAssertEqual(event.previousStatus, .healthy)
        XCTAssertEqual(event.operation, .watchdog)
        XCTAssertEqual(event.eventType, .domainErrorObserved)
        XCTAssertEqual(event.vmState, .running)
        XCTAssertEqual(event.vmErrors, [.missingIPAddress])
        XCTAssertEqual(event.failureReasons, [.guestHTTP("503")])
        XCTAssertEqual(event.vitalDBObservation, observation)
    }

    func testDocumentEventUsesExplicitTimestampAndSource() {
        let event = factory().documentEvent(
            source: "host-command",
            eventType: .runtimeCommandCompleted,
            timestamp: "2026-05-30T00:00:02Z",
            operation: .repairProxy,
            message: "command completed"
        )

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.source, "host-command")
        XCTAssertEqual(event.timestamp, "2026-05-30T00:00:02Z")
        XCTAssertEqual(event.product, "VitalServerHelper")
        XCTAssertEqual(event.runtimeVersion, "1.2.3")
        XCTAssertEqual(event.eventType, .runtimeCommandCompleted)
        XCTAssertEqual(event.operation, .repairProxy)
        XCTAssertEqual(event.failureReasons, [])
    }

    func testObservedStatusEventSuppressesTransientFailureReasonsDuringInitialization() {
        let event = factory().observedStatusEvent(
            status: .initializing,
            previousStatus: .installing,
            operation: .install,
            message: "runtime initialized; runtime services starting",
            healthSnapshot: RuntimeHealthSnapshot(
                vmExecutable: .executable,
                proxyExecutable: .executable,
                rootfsBase: .present,
                vmDisk: .present,
                vmService: .loaded,
                proxyService: .loaded,
                watchdogService: .loaded,
                vmState: .unreachable,
                vmErrors: [],
                vmIP: nil,
                proxyPort: 80,
                hostProxyHTTP: "failed",
                guestHTTP: "missing-vm-ip",
                redisUIHTTP: "missing",
                swaggerUIHTTP: "missing",
                failureReasons: [
                    .guestRuntimeStateMissing,
                    .hostProxyHTTP("failed"),
                    .auditProxyHTTP("failed"),
                    .containerObservationMissing,
                ]
            ),
            eventType: .statusChanged
        )

        XCTAssertEqual(event.status, RuntimeStatusLevel.initializing)
        XCTAssertEqual(event.failureReasons, [RuntimeFailureReason]())
    }

    func testCommandEventFormatsCommandContextWithExecutionAndOutputIssues() {
        let event = factory().commandEvent(
            .runtimeCommandFailed,
            executable: "/bin/tool",
            arguments: ["--start"],
            result: RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: "launch denied",
                outputIssues: [
                    RuntimeCommandOutputIssue(
                        stream: .stderr,
                        message: "command stderr is not valid UTF-8"
                    ),
                ],
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .processLaunchFailed,
                    message: "launch denied"
                )
            )
        )

        XCTAssertEqual(event.source, "host-command")
        XCTAssertEqual(event.eventType, .runtimeCommandFailed)
        XCTAssertEqual(
            event.message,
            "command runtime-command-failed executable=/bin/tool arguments=--start exitCode=127 executionIssue=processLaunchFailed: launch denied outputIssues=stderr: command stderr is not valid UTF-8"
        )
    }

    private func factory() -> RuntimeEventFactory {
        RuntimeEventFactory(
            id: { "event-1" },
            timestamp: { "2026-05-30T00:00:01Z" },
            product: "VitalServerHelper",
            runtimeVersion: { "1.2.3" }
        )
    }
}
