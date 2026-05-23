import RuntimeCore
import RuntimeContracts
@testable import HostRuntimeControl
import XCTest

final class RuntimeWatchdogRunnerTests: XCTestCase {
    func testSkipsRecoveryDuringActiveManagedOperation() throws {
        let harness = WatchdogHarness(activeOperation: .applyBundle)

        try harness.runner.run()

        XCTAssertEqual(harness.prepareLogCalls, 1)
        XCTAssertEqual(harness.healthCalls, 0)
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertTrue(harness.writtenStatuses.isEmpty)
    }

    func testHealthyRuntimeWritesHealthyStatusWithoutRecovery() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.healthCalls, 1)
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.healthy])
        XCTAssertTrue(harness.restartedServices.isEmpty)
        XCTAssertEqual(harness.sleepCalls, [])
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
        XCTAssertTrue(harness.restartedServices.isEmpty)
    }

    func testGuestReadinessFailureRestartsOnlyVMWhenProxyIsAlive() throws {
        let harness = WatchdogHarness(snapshots: [
            healthSnapshot(
                hostProxyHTTP: "502",
                guestHTTP: "503",
                failureReasons: [.hostProxyHTTP("502"), .guestHTTP("503")]
            ),
            healthSnapshot(),
        ])

        try harness.runner.run()

        XCTAssertEqual(harness.proxyLivenessPorts, [80])
        XCTAssertEqual(harness.restartedServices, [.vm])
        XCTAssertEqual(harness.sleepCalls, [Constants.Runtime.watchdogRecoveryWaitSeconds])
        XCTAssertEqual(harness.writtenStatuses.map(\.status), [.recovering, .healthy])
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
}

private final class WatchdogHarness {
    var prepareLogCalls = 0
    var healthCalls = 0
    var proxyLivenessPorts: [Int] = []
    var restartedServices: [RuntimeManagedService] = []
    var sleepCalls: [TimeInterval] = []
    var writtenStatuses: [(status: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
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

    var runner: RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
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
                proxyLivenessHTTP: { port in
                    self.proxyLivenessPorts.append(port)
                    return "204"
                },
                automaticRecoveryEnabled: {
                    self.automaticRecoveryEnabled
                },
                restartService: { label in
                    self.restartedServices.append(label)
                },
                sleep: { interval in
                    self.sleepCalls.append(interval)
                },
                writeStatus: { status, operation, message in
                    self.writtenStatuses.append((status, operation, message))
                }
            ),
            log: { message in
                self.logs.append(message)
            }
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
        vmIP: vmIP,
        proxyPort: proxyPort,
        hostProxyHTTP: hostProxyHTTP,
        guestHTTP: guestHTTP,
        redisUIHTTP: redisUIHTTP,
        swaggerUIHTTP: swaggerUIHTTP,
        failureReasons: failureReasons
    )
}
