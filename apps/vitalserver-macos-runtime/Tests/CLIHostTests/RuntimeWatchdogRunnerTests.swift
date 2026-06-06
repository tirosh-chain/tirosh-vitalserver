import Contracts
import Application
import Domain
import XCTest
import Errors

private let watchdogRecoveryWaitSeconds = 20.0

final class RuntimeWatchdogRunnerTests: XCTestCase {
    func testSkipsRecoveryDuringActiveManagedOperation() throws {
        let harness = WatchdogHarness(activeOperation: .applyBundle)

        try harness.runner.run()

        XCTAssertEqual(harness.prepareLogCalls, 1)
        XCTAssertEqual(harness.healthCalls, 0)
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertTrue(harness.writtenStatuses.isEmpty)
        XCTAssertEqual(harness.lifecycleEvents.map(\.eventType), [.watchdogSkipped])
    }

    func testHealthyRuntimeWritesHealthyStatusWithoutRecovery() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.healthCalls, 1)
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.healthy])
        XCTAssertEqual(harness.observedStatuses.map(\.status), [.healthy])
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertEqual(harness.sleepCalls, [])
    }

    func testHealthyRuntimeMarksBootstrappingVMLifecycleRunningBeforeStatusWrite() throws {
        let lifecycle = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            operation: .startServices,
            startedAt: "2026-05-31T00:00:00Z",
            updatedAt: "2026-05-31T00:00:01Z",
            deadlineAt: "2026-05-31T00:10:00Z"
        )
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(vmLifecycle: lifecycle, vmState: .starting),
            healthSnapshot(
                vmLifecycle: RuntimeVMLifecycleDocument(
                    state: .running,
                    operation: .startServices,
                    startedAt: "2026-05-31T00:00:00Z",
                    updatedAt: "2026-05-31T00:02:00Z"
                )
            ),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.healthCalls, 2)
        XCTAssertEqual(harness.runningLifecycleStates, [.bootstrapping])
        XCTAssertEqual(harness.lifecycleEvents.map(\.eventType), [.statusChanged])
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.healthy])
        XCTAssertEqual(harness.observedStatuses.last?.snapshot.vmLifecycle?.state, .running)
        XCTAssertEqual(harness.observedStatuses.last?.snapshot.vmState, .running)
    }

    func testDisabledAutoRecoveryWritesDegradedStatusWithoutRestart() throws {
        let harness = WatchdogHarness(
            automaticRecoveryEnabled: false,
            snapshots: [
                healthSnapshot(guestHTTP: "503", failureReasons: [.guestHTTP("503")]),
            ]
        )

        try harness.runner.run()

        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.recovering, .degraded])
        XCTAssertEqual(harness.observedStatuses.map(\.status), [.recovering, .degraded])
        XCTAssertEqual(harness.observedStatuses.last?.snapshot.failureReasons, [.guestHTTP("503")])
        XCTAssertTrue(harness.restartedServices.isEmpty)
    }

    func testGuestReadinessFailureRestartsVMGuestLogSyncAndProxy() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(
                vmLifecycle: runningLifecycle(),
                hostProxyHTTP: "502",
                guestHTTP: "503",
                failureReasons: [.hostProxyHTTP("502"), .guestHTTP("503")]
            ),
            healthSnapshot(),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.proxyLivenessPorts, [80])
        XCTAssertEqual(harness.vmRuntimeRestartCalls, 1)
        XCTAssertEqual(harness.restartedServices, [.proxy])
        XCTAssertEqual(harness.sleepCalls, [watchdogRecoveryWaitSeconds])
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.recovering, .healthy])
        XCTAssertEqual(harness.observedStatuses.map(\.status), [.recovering, .healthy])
        XCTAssertEqual(harness.observedEvents.map(\.eventType), [
            .recoveryPlanned,
            .serviceRestartDispatched,
            .serviceRestartDispatched,
        ])
    }

    func testMissingInstalledArtifactWritesCriticalWithoutRestart() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(
                vmExecutable: false,
                failureReasons: [.missingVMBin]
            ),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.recovering, .critical])
        XCTAssertTrue(harness.restartedServices.isEmpty)
    }

    func testGuestStorageFailureSuppressesAutomaticRecoveryWithoutRestart() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(
                vmErrors: [.guestFilesystemReadOnly],
                guestHTTP: "failed",
                failureReasons: [.guestHTTP("failed")]
            ),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.proxyLivenessPorts, [])
        XCTAssertEqual(harness.vmRuntimeRestartCalls, 0)
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.critical])
        XCTAssertEqual(harness.observedEvents.map(\.eventType), [.recoverySuppressed])
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertEqual(harness.sleepCalls, [])
    }

    func testBootstrappingVMLifecycleDefersRecoveryWithoutRestart() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(
                vmLifecycle: RuntimeVMLifecycleDocument(
                    state: .bootstrapping,
                    startedAt: "2026-05-31T00:00:00Z",
                    updatedAt: "2026-05-31T00:00:01Z",
                    deadlineAt: "2999-01-01T00:00:00Z"
                ),
                vmState: .starting,
                vmIP: nil,
                guestHTTP: RuntimeHTTPStatusText.missingVMIP,
                failureReasons: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)]
            ),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.proxyLivenessPorts, [])
        XCTAssertEqual(harness.vmRuntimeRestartCalls, 0)
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.degraded])
        XCTAssertEqual(harness.observedEvents.map(\.eventType), [.recoveryDeferred])
    }
}

private final class WatchdogHarness {
    var prepareLogCalls = 0
    var healthCalls = 0
    var proxyLivenessPorts: [Int] = []
    var vmRuntimeRestartCalls = 0
    var restartedServices: [RuntimeManagedService] = []
    var sleepCalls: [TimeInterval] = []
    var runningLifecycleStates: [RuntimeVMLifecycleState] = []
    var writtenStatuses: [(status: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var observedStatuses: [
        (status: RuntimeStatusLevel, operation: RuntimeOperation, message: String, snapshot: RuntimeHealthSnapshot)
    ] = []
    var observedEvents: [
        (
            status: RuntimeStatusLevel,
            operation: RuntimeOperation,
            message: String,
            snapshot: RuntimeHealthSnapshot,
            eventType: RuntimeEventType
        )
    ] = []
    var lifecycleEvents: [(operation: RuntimeOperation, message: String, eventType: RuntimeEventType)] = []
    var logs: [String] = []

    private let activeOperation: RuntimeOperation?
    private let automaticRecoveryEnabled: Bool
    private var snapshots: [RuntimeHealthSnapshot]

    init(
        activeOperation: RuntimeOperation? = nil,
        automaticRecoveryEnabled: Bool = true,
        snapshots: [RuntimeHealthSnapshot] = [healthSnapshot()]
    ) {
        self.activeOperation = activeOperation
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.snapshots = snapshots
    }

    var runner: WatchdogHarnessRunner {
        WatchdogHarnessRunner(
            operations: RunWatchdogRuntimeOperations(
                prepareLogs: {
                    self.prepareLogCalls += 1
                },
                activeManagedOperation: {
                    self.activeOperation
                },
                healthSnapshot: {
                    self.healthCalls += 1
                    return self.snapshots.removeFirst()
                },
                executeInitialSnapshotDecision: { decision, snapshot in
                    try self.executeInitialSnapshotDecision(decision, snapshot: snapshot)
                },
                proxyLivenessHTTP: { port in
                    self.proxyLivenessPorts.append(port)
                    return "204"
                },
                automaticRecoveryEnabled: {
                    self.automaticRecoveryEnabled
                },
                executeRecoveryDecision: { decision, snapshot in
                    try self.executeRecoveryDecision(decision, snapshot: snapshot)
                },
                recordLifecycleEvent: { operation, message, eventType in
                    self.lifecycleEvents.append((operation, message, eventType))
                }
            ),
            log: { message in
                self.logs.append(message)
            },
            printLine: { _ in }
        )
    }

    private func executeInitialSnapshotDecision(
        _ decision: WatchdogRuntimeInitialSnapshotDecision,
        snapshot: RuntimeHealthSnapshot
    ) throws -> RunWatchdogRuntimeInitialSnapshotExecutionResult {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot)
            writtenStatuses.append((.healthy, .watchdog, plan.statusMessage))
            observedStatuses.append((.healthy, .watchdog, plan.statusMessage, finalized))
            return .handled
        case .recoverySuppressed(let plan):
            writeObservedStatus(plan, snapshot: snapshot)
            return .handled
        case .recoveryDeferred(let plan):
            writeObservedStatus(plan, snapshot: snapshot)
            return .handled
        case .needsRecoveryProbe:
            return .needsRecoveryProbe
        }
    }

    private func writeObservedStatus(
        _ plan: WatchdogRuntimeObservedStatusPlan,
        snapshot: RuntimeHealthSnapshot
    ) {
        if let logMessage = plan.logMessage {
            logs.append(logMessage)
        }
        writtenStatuses.append((plan.status, .watchdog, plan.message))
        observedStatuses.append((plan.status, .watchdog, plan.message, snapshot))
        observedEvents.append((plan.status, .watchdog, plan.message, snapshot, plan.eventType))
    }

    private func completeHealthyVMLifecycleIfNeeded(_ snapshot: RuntimeHealthSnapshot) -> RuntimeHealthSnapshot {
        let plan = WatchdogRuntimeUseCase().lifecycleMarkPlan(snapshot)
        guard let lifecycle = plan.lifecycle else {
            return snapshot
        }
        runningLifecycleStates.append(lifecycle.state)
        lifecycleEvents.append((.watchdog, plan.eventMessage, .statusChanged))
        healthCalls += 1
        return snapshots.removeFirst()
    }

    private func executeRecoveryDecision(
        _ decision: WatchdogRuntimeRecoveryDecision,
        snapshot: RuntimeHealthSnapshot
    ) throws {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot)
            writtenStatuses.append((.healthy, .watchdog, plan.statusMessage))
            observedStatuses.append((.healthy, .watchdog, plan.statusMessage, finalized))
        case .recoveryDisabled(let plan):
            writeTerminalRecoveryStatus(plan, snapshot: snapshot)
        case .recoveryDeferred(let plan):
            writeObservedStatus(plan, snapshot: snapshot)
        case .recoverySuppressed(let plan):
            writeObservedStatus(plan, snapshot: snapshot)
        case .unrecoverable(let plan):
            writeTerminalRecoveryStatus(plan, snapshot: snapshot)
        case .recover(let plan):
            try recover(plan, initial: snapshot)
        }
    }

    private func writeTerminalRecoveryStatus(
        _ plan: WatchdogRuntimeTerminalRecoveryPlan,
        snapshot: RuntimeHealthSnapshot
    ) {
        logs.append(plan.detectedLogMessage)
        writtenStatuses.append((.recovering, .watchdog, plan.startedStatusMessage))
        observedStatuses.append((.recovering, .watchdog, plan.startedStatusMessage, snapshot))
        writtenStatuses.append((plan.finalStatus, .watchdog, plan.finalStatusMessage))
        observedStatuses.append((plan.finalStatus, .watchdog, plan.finalStatusMessage, snapshot))
    }

    private func recover(
        _ plan: WatchdogRuntimeRecoveryExecutionPlan,
        initial: RuntimeHealthSnapshot
    ) throws {
        let useCase = WatchdogRuntimeUseCase()
        logs.append(plan.detectedLogMessage)
        writtenStatuses.append((.recovering, .watchdog, plan.startedStatusMessage))
        observedStatuses.append((.recovering, .watchdog, plan.startedStatusMessage, initial))
        logs.append(plan.planLogMessage)
        observedEvents.append((.recovering, .watchdog, plan.plannedEventMessage, initial, .recoveryPlanned))

        if let vmRestartEventMessage = plan.vmRestartEventMessage {
            observedEvents.append((.recovering, .watchdog, vmRestartEventMessage, initial, .serviceRestartDispatched))
            vmRuntimeRestartCalls += 1
        }
        if let proxyRestartEventMessage = plan.proxyRestartEventMessage {
            observedEvents.append((.recovering, .watchdog, proxyRestartEventMessage, initial, .serviceRestartDispatched))
            restartedServices.append(.proxy)
        }

        sleepCalls.append(watchdogRecoveryWaitSeconds)
        healthCalls += 1
        let recovered = snapshots.removeFirst()
        let completionPlan = useCase.recoveryCompletionPlan(recovered)
        writtenStatuses.append((completionPlan.status, .watchdog, completionPlan.message))
        observedStatuses.append((completionPlan.status, .watchdog, completionPlan.message, recovered))
    }
}

private struct WatchdogHarnessRunner {
    let operations: RunWatchdogRuntimeOperations
    let log: (String) -> Void
    let printLine: (String) -> Void

    func run() throws {
        try RunWatchdogRuntimeUseCase().run(
            operations: operations,
            log: log,
            printLine: printLine
        )
    }
}

private func healthSnapshot(
    vmExecutable: Bool = true,
    proxyExecutable: Bool = true,
    rootfsBase: RuntimeFileState = .present,
    vmDisk: RuntimeFileState = .present,
    vmService: RuntimeServiceState = .loaded,
    proxyService: RuntimeServiceState = .loaded,
    watchdogService: RuntimeServiceState = .loaded,
    vmLifecycle: RuntimeVMLifecycleDocument? = nil,
    vmState: RuntimeVMState = .running,
    vmErrors: [RuntimeVMError] = [],
    vmIP: String? = "192.168.64.2",
    proxyPort: Int = 80,
    hostProxyHTTP: String = "200",
    guestHTTP: String = "200",
    redisUIHTTP: String = "200",
    swaggerUIHTTP: String = "200",
    failureReasons: [RuntimeFailureReason] = []
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: vmExecutable,
        proxyExecutable: proxyExecutable,
        rootfsBase: rootfsBase,
        vmDisk: vmDisk,
        vmService: vmService,
        proxyService: proxyService,
        watchdogService: watchdogService,
        vmLifecycle: vmLifecycle,
        vmState: vmState,
        vmErrors: vmErrors,
        vmIP: vmIP,
        proxyPort: proxyPort,
        hostProxyHTTP: hostProxyHTTP,
        guestHTTP: guestHTTP,
        redisUIHTTP: redisUIHTTP,
        swaggerUIHTTP: swaggerUIHTTP,
        failureReasons: failureReasons
    )
}

private func runningLifecycle() -> RuntimeVMLifecycleDocument {
    RuntimeVMLifecycleDocument(
        state: .running,
        startedAt: "2026-05-31T00:00:00Z",
        updatedAt: "2026-05-31T00:00:01Z"
    )
}
