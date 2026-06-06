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

    func testWaitExecutesPortsAndCompletesWhenRuntimeBecomesHealthy() throws {
        let harness = HealthWaitUseCaseHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: []),
        ])

        let outcome = try harness.useCase.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            ),
            context: harness.context,
            operations: harness.operations
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(harness.events.contains("sleep"))
        XCTAssertTrue(harness.events.contains("status:recovering:health:waiting for runtime health: host-proxy-http-000"))
        XCTAssertTrue(harness.events.contains("log:runtime health ok hostProxyHTTP=200"))
    }

    func testWaitExecutionPreservesEarlyFailureAndTimeoutWithoutWorkflowJudgement() {
        let failedEarly = HealthWaitUseCaseHarness(snapshots: [
            healthSnapshot(reasons: [.guestBootstrapFailed]),
        ])

        XCTAssertThrowsError(try failedEarly.useCase.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: false
            ),
            context: failedEarly.context,
            operations: failedEarly.operations
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health failed early reason=guest-bootstrap-failed"
            )
        }
        XCTAssertTrue(failedEarly.events.contains("log:runtime health failed early reason=guest-bootstrap-failed"))

        let timedOut = HealthWaitUseCaseHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: [.guestHTTP("000")]),
        ])
        XCTAssertThrowsError(try timedOut.useCase.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            ),
            context: timedOut.context,
            operations: timedOut.operations
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health timed out reasons=host-proxy-http-000, guest-http-000"
            )
        }
    }
}

private final class HealthWaitUseCaseHarness {
    let useCase = WaitForRuntimeHealthUseCase()
    let context = RuntimeHealthWaitExecutionContext(
        timeoutSeconds: 6,
        pollIntervalSeconds: 3,
        progressEveryAttempts: 1
    )
    var snapshots: [RuntimeHealthSnapshot]
    var events: [String] = []
    var serviceStates: [RuntimeManagedService: RuntimeServiceState] = [
        .vm: .loaded,
        .guestLogSync: .loaded,
        .proxy: .loaded,
        .watchdog: .loaded,
    ]

    lazy var operations = RuntimeHealthWaitOperations(
        serviceStates: { services in
            Dictionary(uniqueKeysWithValues: services.map { service in
                (service, self.serviceStates[service] ?? .notLoaded)
            })
        },
        healthSnapshot: {
            if self.snapshots.count > 1 {
                return self.snapshots.removeFirst()
            }
            return self.snapshots[0]
        },
        writeStatusBestEffort: { status, operation, message in
            self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
        },
        sleep: {
            self.events.append("sleep")
        },
        log: { message in
            self.events.append("log:\(message)")
        }
    )

    init(snapshots: [RuntimeHealthSnapshot]) {
        self.snapshots = snapshots
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
