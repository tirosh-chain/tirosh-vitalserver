import Application
import Contracts
import XCTest
import Errors

final class RefreshRuntimeHealthUseCaseTests: XCTestCase {
    func testRefreshReturnsHealthyDecisionWhenSnapshotIsHealthy() {
        let useCase = RefreshRuntimeHealthUseCase()

        let decision = useCase.decision(snapshot: healthSnapshot(reasons: []))

        XCTAssertTrue(decision.healthy)
        XCTAssertEqual(decision.status, .healthy)
        XCTAssertEqual(decision.operation, .health)
        XCTAssertEqual(decision.statusMessage, "runtime health check passed")
        XCTAssertNil(decision.observedEventMessage)
        XCTAssertEqual(decision.outputLine, "health: ok")
    }

    func testRefreshReturnsUnhealthyDecisionWithVMErrorMessage() {
        let useCase = RefreshRuntimeHealthUseCase()

        let decision = useCase.decision(snapshot: healthSnapshot(reasons: [.vmService("not-loaded")]))

        XCTAssertFalse(decision.healthy)
        XCTAssertEqual(decision.status, .degraded)
        XCTAssertEqual(decision.statusMessage, "runtime health check failed: vm-service-not-loaded")
        XCTAssertEqual(decision.observedEventMessage, "runtime VM errors observed: vm-service-state-not-loaded")
        XCTAssertEqual(decision.outputLine, "health: failed")
    }

    func testRefreshReturnsUnhealthyDecisionWithDomainErrorMessage() {
        let useCase = RefreshRuntimeHealthUseCase()

        let decision = useCase.decision(snapshot: healthSnapshot(reasons: [.auditProxyHTTP("failed")]))

        XCTAssertFalse(decision.healthy)
        XCTAssertEqual(decision.statusMessage, "runtime health check failed: audit-proxy-http-failed")
        XCTAssertEqual(decision.observedEventMessage, "runtime domain errors observed: audit-proxy-http-failed")
    }

    func testObservedEventTypeIsSelectedByUseCaseFromSnapshot() {
        let useCase = RefreshRuntimeHealthUseCase()

        XCTAssertEqual(
            useCase.observedEventType(
                snapshot: healthSnapshot(reasons: [.guestHTTP("503")]),
                defaultEventType: .healthObserved
            ),
            .domainErrorObserved
        )
        XCTAssertEqual(
            useCase.observedEventType(
                snapshot: healthSnapshot(reasons: []),
                defaultEventType: .healthObserved
            ),
            .healthObserved
        )
    }

    func testRefreshExecutionWritesHealthyStatus() throws {
        let sink = RefreshHealthEventSink()
        let operations = operations(
            snapshot: healthSnapshot(reasons: []),
            sink: sink
        )

        let decision = try RefreshRuntimeHealthUseCase().refresh(operations: operations)

        XCTAssertTrue(decision.healthy)
        XCTAssertEqual(sink.events, [
            "status:healthy:health:runtime health check passed",
        ])
    }

    func testRefreshExecutionWritesUnhealthyStatusAndEventBestEffortBeforeFailing() {
        let sink = RefreshHealthEventSink()
        let operations = operations(
            snapshot: healthSnapshot(reasons: [.auditProxyHTTP("failed")]),
            sink: sink
        )

        XCTAssertThrowsError(try RefreshRuntimeHealthUseCase().refresh(operations: operations)) { error in
            XCTAssertEqual(
                error as? RefreshRuntimeHealthUseCaseError,
                .operationFailed("runtime health check failed: audit-proxy-http-failed")
            )
        }
        XCTAssertEqual(sink.events, [
            "best-effort-status:degraded:health:runtime health check failed: audit-proxy-http-failed",
            "best-effort-event:degraded:health:runtime domain errors observed: audit-proxy-http-failed",
        ])
    }

    private func operations(
        snapshot: RuntimeHealthSnapshot,
        sink: RefreshHealthEventSink
    ) -> RefreshRuntimeHealthOperations {
        RefreshRuntimeHealthOperations(
            healthSnapshot: { snapshot },
            writeStatus: { status, operation, message in
                sink.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            writeStatusBestEffort: { status, operation, message in
                sink.events.append("best-effort-status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            recordObservedEventBestEffort: { status, operation, message, _ in
                sink.events.append("best-effort-event:\(status.rawValue):\(operation.rawValue):\(message)")
            }
        )
    }
}

private final class RefreshHealthEventSink {
    var events: [String] = []
}

private func healthSnapshot(reasons: [RuntimeFailureReason]) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmErrors: reasons.compactMap { reason in
            if case .vmService(let state) = reason {
                return .serviceNotLoaded(state)
            }
            return nil
        },
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
