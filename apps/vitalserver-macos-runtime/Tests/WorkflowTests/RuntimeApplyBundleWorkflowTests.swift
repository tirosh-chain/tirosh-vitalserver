import Contracts
import Application
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeApplyBundleWorkflowTests: XCTestCase {
    func testRunExecutesApplyBundlePlanAndWritesHealthyStatus() throws {
        let harness = ApplyBundleHarness()

        try harness.run()

        XCTAssertEqual(harness.executedSteps, RuntimeOperationPlans.applyBundle(updatesRootfsBase: false).steps)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertEqual(harness.statuses.last?.message, "bundle applied: 0.1.4")
        XCTAssertEqual(harness.pruneCount, 1)
        XCTAssertTrue(harness.logs.contains("bundle applied path=/tmp/staged-bundle"))
    }

    func testRunWritesCriticalStatusWhenPreflightFails() throws {
        let harness = ApplyBundleHarness()
        harness.preflightError = TestApplyBundleError.preflight

        XCTAssertThrowsError(try harness.run())

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("bundle apply preflight failed") == true)
        XCTAssertTrue(harness.statuses.last?.message.contains("described:preflight") == true)
    }

    func testRunRollsBackAndMarksDegradedWhenStepFails() throws {
        let harness = ApplyBundleHarness()
        harness.stepError = TestApplyBundleError.step

        XCTAssertThrowsError(try harness.run())

        XCTAssertEqual(harness.rollbackBackup, harness.preflight.backup)
        XCTAssertNil(harness.restartedPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback completed") == true)
        XCTAssertTrue(harness.statuses.last?.message.contains("described:step") == true)
    }

    func testRunUsesGuestPoweroffStopPathWhenVMRestartIsRequired() throws {
        let harness = ApplyBundleHarness()

        try harness.run()

        XCTAssertEqual(harness.guestPoweroffStopVersions, ["0.1.4"])
        XCTAssertEqual(harness.directStopCount, 0)
    }

    func testRunClearsGuestShutdownPreparationAndRollsBackWhenGuestPoweroffStopFails() throws {
        let harness = ApplyBundleHarness()
        harness.stopAfterGuestPoweroffError = TestApplyBundleError.stopAfterGuestPoweroff

        XCTAssertThrowsError(try harness.run())

        XCTAssertEqual(harness.guestPoweroffStopVersions, ["0.1.4"])
        XCTAssertEqual(harness.rollbackBackup, harness.preflight.backup)
        XCTAssertNil(harness.restartedPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback completed") == true)
        XCTAssertTrue(harness.statuses.last?.message.contains("described:stopAfterGuestPoweroff") == true)
    }

    func testRunClearsGuestShutdownPreparationAndRollsBackWhenGuestShutdownPreparationFails() throws {
        let harness = ApplyBundleHarness()
        harness.prepareGuestShutdownError = TestApplyBundleError.prepareGuestShutdown

        XCTAssertThrowsError(try harness.run())

        XCTAssertEqual(harness.guestPoweroffStopVersions, ["0.1.4"])
        XCTAssertEqual(harness.rollbackBackup, harness.preflight.backup)
        XCTAssertNil(harness.restartedPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback completed") == true)
        XCTAssertTrue(harness.statuses.last?.message.contains("described:prepareGuestShutdown") == true)
    }

    func testRunMarksCriticalWhenRollbackAlsoFails() throws {
        let harness = ApplyBundleHarness()
        harness.stepError = TestApplyBundleError.step
        harness.rollbackError = TestApplyBundleError.rollback

        XCTAssertThrowsError(try harness.run())

        XCTAssertEqual(harness.rollbackBackup, harness.preflight.backup)
        XCTAssertEqual(harness.restartedPolicy, harness.preflight.restartPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback failed") == true)
        XCTAssertTrue(harness.statuses.last?.message.contains("described:rollback") == true)
    }

    func testRunKeepsApplySuccessfulWhenArtifactCleanupFails() throws {
        let harness = ApplyBundleHarness()
        harness.pruneError = TestApplyBundleError.prune

        try harness.run()

        XCTAssertEqual(harness.pruneCount, 1)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertEqual(harness.statuses.last?.message, "bundle applied: 0.1.4")
        XCTAssertTrue(harness.logs.contains { $0.contains("runtime artifact cleanup failed after bundle apply") })
        XCTAssertTrue(harness.logs.contains { $0.contains("described:prune") })
    }
}

private final class ApplyBundleHarness {
    let inputBundle = URL(fileURLWithPath: "/tmp/input-bundle")
    let preflight = ApplyBundlePreflightContext(
        stagedBundle: URL(fileURLWithPath: "/tmp/staged-bundle"),
        manifest: UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "0.1.4",
            releaseLabel: "0.1.4",
            targetPlatform: "macos-arm64",
            components: ["updater": "0.1.4"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: [],
            migrations: []
        ),
        stagedRootfs: nil,
        backup: URL(fileURLWithPath: "/tmp/backup"),
        restartPolicy: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: true,
            restartWatchdog: false
        )
    )

    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedSteps: [RuntimeWorkflowStep] = []
    var guestPoweroffStopVersions: [String] = []
    var logs: [String] = []
    var pruneCount = 0
    var directStopCount = 0
    var rollbackBackup: URL?
    var restartedPolicy: RuntimeServiceRestartPolicy?
    var preflightError: Error?
    var stepError: Error?
    var prepareGuestShutdownError: Error?
    var stopAfterGuestPoweroffError: Error?
    var rollbackError: Error?
    var pruneError: Error?

    func run() throws {
        try RuntimeApplyBundleWorkflow().run(
            input: ApplyRuntimeBundleInput(bundleURL: inputBundle),
            operations: operations
        )
    }

    var operations: ApplyRuntimeBundleOperations {
        ApplyRuntimeBundleOperations(
            prepareLogs: {},
            initialHealthSnapshot: {
                RuntimeHealthSnapshot(
                    vmExecutable: .executable,
                    proxyExecutable: .executable,
                    rootfsBase: .present,
                    vmDisk: .present,
                    vmService: .loaded,
                    proxyService: .loaded,
                    watchdogService: .loaded,
                    vmState: .running,
                    vmIP: "192.168.64.2",
                    proxyPort: 80,
                    hostProxyHTTP: "200",
                    guestHTTP: "200",
                    redisUIHTTP: "200",
                    swaggerUIHTTP: "200",
                    failureReasons: []
                )
            },
            preparePreflight: { _ in
                if let preflightError = self.preflightError {
                    throw preflightError
                }
                return self.preflight
            },
            rootfsBase: URL(fileURLWithPath: "/tmp/rootfs-base"),
            prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: { manifest in
                try self.executeApplyStep(.stopRuntimeServices)
                self.guestPoweroffStopVersions.append(manifest.helperVersion)
                if let prepareGuestShutdownError = self.prepareGuestShutdownError {
                    throw prepareGuestShutdownError
                }
                if let stopAfterGuestPoweroffError = self.stopAfterGuestPoweroffError {
                    throw stopAfterGuestPoweroffError
                }
            },
            stopRuntimeServices: {
                self.directStopCount += 1
                try self.executeApplyStep(.stopRuntimeServices)
            },
            createDirectory: { _, _ in },
            fileSize: { _ in 1 },
            replaceFile: { _, _ in
                try self.executeApplyStep(.replaceRootfsBase)
            },
            replaceUpdateArtifacts: { _, _ in
                try self.executeApplyStep(.replaceUpdateArtifacts)
            },
            runMigrations: { _, _ in
                try self.executeApplyStep(.runMigrations)
            },
            refreshCloudInitSeedIfNeeded: { _ in
                try self.executeApplyStep(.refreshCloudInitSeed)
            },
            writeRuntimeVersion: { _, _ in
                try self.executeApplyStep(.writeRuntimeVersion)
            },
            startRuntimeServices: { policy in
                self.restartedPolicy = policy
                if self.rollbackBackup == nil {
                    try self.executeApplyStep(.startRuntimeServices)
                }
            },
            activateGuestUpdateIfNeeded: { _ in
                try self.executeApplyStep(.activateGuestUpdate)
            },
            waitForHealth: { _ in
                try self.executeApplyStep(.waitRuntimeHealth)
            },
            rollback: { backup in
                self.rollbackBackup = backup
                if let rollbackError = self.rollbackError {
                    throw rollbackError
                }
            },
            writeStatus: { level, operation, message in
                self.statuses.append((level: level, operation: operation, message: message))
            },
            writeBestEffortStatus: { level, operation, message in
                self.statuses.append((level: level, operation: operation, message: message))
            },
            publishProgress: { event in
                self.progressEvents.append(event)
            },
            pruneOldRuntimeArtifacts: {
                self.pruneCount += 1
                if let pruneError = self.pruneError {
                    throw pruneError
                }
            },
            describeError: { error in
                "described:\(String(describing: error))"
            },
            log: { message in
                self.logs.append(message)
            }
        )
    }

    func executeApplyStep(_ step: RuntimeWorkflowStep) throws {
        executedSteps.append(step)
        if let stepError {
            throw stepError
        }
    }
}

private enum TestApplyBundleError: Error {
    case preflight
    case step
    case prepareGuestShutdown
    case stopAfterGuestPoweroff
    case rollback
    case prune
}
