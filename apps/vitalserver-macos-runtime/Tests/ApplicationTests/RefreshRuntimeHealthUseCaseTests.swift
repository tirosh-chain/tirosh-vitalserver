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
