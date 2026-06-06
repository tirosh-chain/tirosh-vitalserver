import Application
import Contracts
import Domain
import XCTest
import Errors

final class WaitForRuntimeHealthUseCaseTests: XCTestCase {
    func testPlansSkipWhenNoRuntimeServiceWasRunning() {
        let useCase = WaitForRuntimeHealthUseCase()

        let plan = useCase.plan(
            policy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            ),
            timeoutSeconds: 30
        )

        XCTAssertFalse(plan.shouldWait)
        XCTAssertEqual(plan.observedServices, [])
        XCTAssertEqual(plan.skippedMessage, "runtime services were not running before apply; skipping health wait")
        XCTAssertNil(plan.startedMessage)
    }

    func testPlansWaitFromExplicitRestartPolicy() {
        let useCase = WaitForRuntimeHealthUseCase()
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: false,
            restartProxy: true,
            restartWatchdog: false
        )

        let plan = useCase.plan(policy: policy, timeoutSeconds: 45)

        XCTAssertTrue(plan.shouldWait)
        XCTAssertEqual(plan.policy, policy)
        XCTAssertEqual(plan.observedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertNil(plan.skippedMessage)
        XCTAssertEqual(plan.startedMessage, "waiting for runtime health timeoutSeconds=45.0")
    }

    func testObserveBuildsExplicitWaitObservationFromServiceStatesAndSnapshot() {
        let useCase = WaitForRuntimeHealthUseCase()
        let states = Dictionary(uniqueKeysWithValues: useCase.observedServices().map { service in
            (service, service == .guestLogSync ? RuntimeServiceState.notLoaded : .loaded)
        })

        let observation = useCase.observation(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            ),
            serviceStates: states,
            snapshot: healthSnapshot(reasons: [])
        )

        XCTAssertEqual(observation.requiredServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(observation.serviceStates[.vm], .loaded)
        XCTAssertEqual(observation.serviceStates[.guestLogSync], .notLoaded)
        XCTAssertEqual(observation.serviceStates[.proxy], .loaded)
        XCTAssertEqual(observation.serviceStates[.watchdog], .loaded)
        XCTAssertEqual(observation.snapshot.hostProxyHTTP, "200")
    }

    func testMissingServiceStateStaysMissingInObservation() {
        let useCase = WaitForRuntimeHealthUseCase()

        let observation = useCase.observation(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            ),
            serviceStates: [:],
            snapshot: healthSnapshot(reasons: [])
        )

        XCTAssertEqual(observation.requiredServices, [.vm])
        XCTAssertNil(observation.serviceStates[.vm])
    }

    func testServiceReadFailureStaysExplicitInObservation() {
        let useCase = WaitForRuntimeHealthUseCase()

        let observation = useCase.observation(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            ),
            serviceStates: [.vm: .permissionDenied("operation not permitted")],
            snapshot: healthSnapshot(reasons: [])
        )

        XCTAssertEqual(observation.serviceStates[.vm], .permissionDenied("operation not permitted"))
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
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
