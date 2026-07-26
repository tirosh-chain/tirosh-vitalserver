import Application
import Contracts
import XCTest
import Errors

final class RuntimeGuestProductServiceControlUseCaseTests: XCTestCase {
    func testStartAndStopServiceReturnGuestOperationWhenServiceAndCommandMatch() throws {
        let gateway = CapturingGuestControlGateway(
            startOperation: guestOperation(command: .start),
            stopOperation: guestOperation(command: .stop)
        )

        let started = try RuntimeGuestProductServiceControlUseCase().startService("app", gateway: gateway)
        let stopped = try RuntimeGuestProductServiceControlUseCase().stopService("app", gateway: gateway)

        XCTAssertEqual(started.command, .start)
        XCTAssertEqual(stopped.command, .stop)
        XCTAssertEqual(gateway.startedServices, ["app"])
        XCTAssertEqual(gateway.stoppedServices, ["app"])
    }

    func testRestartServiceReturnsGuestOperationWhenServiceAndCommandMatch() throws {
        let operation = guestOperation(command: .restart)
        let gateway = CapturingGuestControlGateway(restartOperation: operation)

        let result = try RuntimeGuestProductServiceControlUseCase().restartService("app", gateway: gateway)

        XCTAssertEqual(result, operation)
        XCTAssertEqual(gateway.restartedServices, ["app"])
    }

    func testReconcileServicesReturnsGuestStackOperation() throws {
        let operation = guestOperation(command: .reconcile, service: "guest-stack")
        let gateway = CapturingGuestControlGateway(reconcileOperation: operation)

        let result = try RuntimeGuestProductServiceControlUseCase().reconcileServices(gateway: gateway)

        XCTAssertEqual(result, operation)
        XCTAssertEqual(gateway.reconcileCount, 1)
    }

    func testRestartServiceFailsWhenGuestOperationReportsAnotherService() {
        let operation = RuntimeGuestControlServiceOperation(
            operationId: "op-redis-restart",
            service: "redis",
            command: .restart,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
        )
        let gateway = CapturingGuestControlGateway(restartOperation: operation)

        XCTAssertThrowsError(try RuntimeGuestProductServiceControlUseCase().restartService("app", gateway: gateway)) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControlError,
                .operationFailed("guest service restart returned mismatched service expected=app actual=redis")
            )
        }
    }

    func testRestartServiceFailsWhenGuestOperationFailureIsExplicit() {
        let operation = RuntimeGuestControlServiceOperation(
            operationId: "op-app-restart",
            service: "app",
            command: .restart,
            state: .failed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            failure: RuntimeGuestControlOperationFailure(
                kind: "composeCommandFailed",
                message: "docker compose restart app failed",
                evidencePath: "/var/log/tirosh/guest-control.log"
            )
        )
        let gateway = CapturingGuestControlGateway(restartOperation: operation)

        XCTAssertThrowsError(try RuntimeGuestProductServiceControlUseCase().restartService("app", gateway: gateway)) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControlError,
                .operationFailed(
                    "guest service operation did not complete service=app operationId=op-app-restart state=failed kind=composeCommandFailed reason=docker compose restart app failed evidencePath=/var/log/tirosh/guest-control.log"
                )
            )
        }
    }

    func testRestartServiceRejectsInterruptedGuestOperation() {
        let operation = RuntimeGuestControlServiceOperation(
            operationId: "op-app-restart",
            service: "app",
            command: .restart,
            state: .interrupted,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            failure: RuntimeGuestControlOperationFailure(
                kind: "controllerRestarted",
                message: "Runtime Controller restarted before the operation outcome was known."
            )
        )
        let gateway = CapturingGuestControlGateway(restartOperation: operation)

        XCTAssertThrowsError(
            try RuntimeGuestProductServiceControlUseCase().restartService(
                "app",
                gateway: gateway
            )
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("controllerRestarted"))
        }
    }
}

private final class CapturingGuestControlGateway: RuntimeGuestControlGateway {
    private let startOperation: RuntimeGuestControlServiceOperation
    private let stopOperation: RuntimeGuestControlServiceOperation
    private let restartOperation: RuntimeGuestControlServiceOperation
    private let reconcileOperation: RuntimeGuestControlServiceOperation
    private(set) var startedServices: [String] = []
    private(set) var stoppedServices: [String] = []
    private(set) var restartedServices: [String] = []
    private(set) var reconcileCount = 0

    init(
        startOperation: RuntimeGuestControlServiceOperation = guestOperation(command: .start),
        stopOperation: RuntimeGuestControlServiceOperation = guestOperation(command: .stop),
        restartOperation: RuntimeGuestControlServiceOperation = guestOperation(command: .restart),
        reconcileOperation: RuntimeGuestControlServiceOperation = guestOperation(
            command: .reconcile,
            service: "guest-stack"
        )
    ) {
        self.startOperation = startOperation
        self.stopOperation = stopOperation
        self.restartOperation = restartOperation
        self.reconcileOperation = reconcileOperation
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        RuntimeGuestControlServiceList(services: [])
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        RuntimeGuestControlStackStatus(
            state: "running",
            observedAt: "2026-07-01T00:00:00+00:00",
            services: []
        )
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        RuntimeGuestControlServiceStatus(
            service: service,
            state: "running",
            health: "healthy",
            observedAt: "2026-07-01T00:00:00+00:00"
        )
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        startedServices.append(service)
        return startOperation
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        stoppedServices.append(service)
        return stopOperation
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        restartedServices.append(service)
        return restartOperation
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        reconcileCount += 1
        return reconcileOperation
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        restartOperation
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        RuntimeGuestControlVitalDBObservationRead(
            state: .unavailable,
            observation: nil,
            readError: "not provided by service-control test gateway"
        )
    }
}

private func guestOperation(
    command: RuntimeGuestControlServiceCommand,
    service: String = "app",
    state: RuntimeGuestControlOperationState = .completed
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: "op-\(service)-\(command.rawValue)",
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00"
    )
}
