import Foundation
import Core
import Contracts
import XCTest
@testable import HostCLI

final class RuntimeApplyBundleRunnerTests: XCTestCase {
    func testRunExecutesApplyBundlePlanAndWritesHealthyStatus() throws {
        let harness = ApplyBundleHarness()

        try harness.runner.run(bundleURL: harness.inputBundle)

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

        XCTAssertThrowsError(try harness.runner.run(bundleURL: harness.inputBundle))

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("bundle apply preflight failed") == true)
    }

    func testRunRollsBackAndMarksDegradedWhenStepFails() throws {
        let harness = ApplyBundleHarness()
        harness.stepError = TestApplyBundleError.step

        XCTAssertThrowsError(try harness.runner.run(bundleURL: harness.inputBundle))

        XCTAssertEqual(harness.rollbackBackup, harness.preflight.backup)
        XCTAssertEqual(harness.restartedPolicy, harness.preflight.restartPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback completed") == true)
    }

    func testRunMarksCriticalWhenRollbackAlsoFails() throws {
        let harness = ApplyBundleHarness()
        harness.stepError = TestApplyBundleError.step
        harness.rollbackError = TestApplyBundleError.rollback

        XCTAssertThrowsError(try harness.runner.run(bundleURL: harness.inputBundle))

        XCTAssertEqual(harness.restartedPolicy, harness.preflight.restartPolicy)
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertTrue(harness.statuses.last?.message.contains("rollback failed") == true)
    }

    func testRunKeepsApplySuccessfulWhenArtifactCleanupFails() throws {
        let harness = ApplyBundleHarness()
        harness.pruneError = TestApplyBundleError.prune

        try harness.runner.run(bundleURL: harness.inputBundle)

        XCTAssertEqual(harness.pruneCount, 1)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertEqual(harness.statuses.last?.message, "bundle applied: 0.1.4")
        XCTAssertTrue(harness.logs.contains { $0.contains("runtime artifact cleanup failed after bundle apply") })
    }
}

private final class ApplyBundleHarness {
    let inputBundle = URL(fileURLWithPath: "/tmp/input-bundle")
    let preflight = ApplyBundlePreflightContext(
        stagedBundle: URL(fileURLWithPath: "/tmp/staged-bundle"),
        manifest: UpdateBundleManifest(
            schemaVersion: 3,
            product: "com.tirosh.vitalserver",
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
            restartProxy: true,
            restartWatchdog: false
        )
    )

    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedSteps: [RuntimeWorkflowStep] = []
    var logs: [String] = []
    var pruneCount = 0
    var rollbackBackup: URL?
    var restartedPolicy: RuntimeServiceRestartPolicy?
    var preflightError: Error?
    var stepError: Error?
    var rollbackError: Error?
    var pruneError: Error?

    var runner: RuntimeApplyBundleRunner {
        RuntimeApplyBundleRunner(
            prepareLogs: {},
            initialHealthSnapshot: {
                RuntimeHealthSnapshot(
                    vmExecutable: true,
                    proxyExecutable: true,
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
            executeStep: { step, _ in
                self.executedSteps.append(step)
                if let stepError = self.stepError {
                    throw stepError
                }
            },
            rollback: { backup in
                self.rollbackBackup = backup
                if let rollbackError = self.rollbackError {
                    throw rollbackError
                }
            },
            startRuntimeServices: { policy in
                self.restartedPolicy = policy
            },
            writeStatus: { level, operation, message in
                self.statuses.append((level: level, operation: operation, message: message))
            },
            writeProgress: { event in
                self.progressEvents.append(event)
            },
            pruneOldRuntimeArtifacts: {
                self.pruneCount += 1
                if let pruneError = self.pruneError {
                    throw pruneError
                }
            },
            reasonText: { reasons in
                reasons.map(\.rawValue).joined(separator: ", ")
            },
            log: { message in
                self.logs.append(message)
            }
        )
    }
}

private enum TestApplyBundleError: Error {
    case preflight
    case step
    case rollback
    case prune
}
