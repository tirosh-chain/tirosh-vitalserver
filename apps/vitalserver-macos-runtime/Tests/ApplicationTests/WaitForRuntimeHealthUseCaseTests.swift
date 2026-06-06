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

    func testUseCaseOwnsWaitProgressAndFailureMessages() {
        let useCase = WaitForRuntimeHealthUseCase()

        let progress = useCase.progressPlan(reasons: [.hostProxyHTTP("503")])

        XCTAssertEqual(progress.status, .recovering)
        XCTAssertEqual(progress.operation, .health)
        XCTAssertEqual(progress.logMessage, "waiting for runtime health reasons=host-proxy-http-503")
        XCTAssertEqual(progress.statusMessage, "waiting for runtime health: host-proxy-http-503")
        XCTAssertEqual(
            useCase.healthyLogMessage(snapshot: healthSnapshot(reasons: [])),
            "runtime health ok hostProxyHTTP=200"
        )
        XCTAssertEqual(
            useCase.failedEarlyMessage(reason: .vmService("not-loaded")),
            "runtime health failed early reason=vm-service-not-loaded"
        )
        XCTAssertEqual(
            useCase.timedOutFailureMessage(reasons: [.guestHTTP("000")]),
            "runtime health timed out reasons=guest-http-000"
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
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
