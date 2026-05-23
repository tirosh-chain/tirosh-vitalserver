import Foundation
import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeRollbackRunnerTests: XCTestCase {
    func testRunExecutesRollbackPlanAndWritesHealthyStatus() throws {
        let harness = RollbackHarness()

        try harness.runner.run(.specificBackup(harness.requestedBackup))

        XCTAssertEqual(harness.commandSeen, .specificBackup(harness.requestedBackup))
        XCTAssertEqual(harness.executedSteps, RuntimeOperationPlans.rollback.steps)
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .started }.map(\.step),
            RuntimeOperationPlans.rollback.steps
        )
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .completed }.map(\.step),
            RuntimeOperationPlans.rollback.steps
        )
        XCTAssertEqual(harness.statuses.first?.level, .recovering)
        XCTAssertEqual(harness.statuses.first?.operation, .rollback)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .rollback)
        XCTAssertEqual(harness.statuses.last?.message, "rollback completed")
        XCTAssertTrue(harness.logs.contains("rollback restored backup=/backup"))
        XCTAssertTrue(harness.logs.contains("mutable VM disk preserved path=/runtime/vm-disk.img"))
    }

    func testRunDoesNotWriteStatusWhenPreflightFails() {
        let harness = RollbackHarness()
        harness.preflightError = TestRollbackError.preflight

        XCTAssertThrowsError(try harness.runner.run(.specificBackup(harness.requestedBackup)))

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertTrue(harness.statuses.isEmpty)
    }

    func testRunPublishesFailedProgressWhenStepFails() {
        let harness = RollbackHarness()
        harness.stepError = TestRollbackError.step

        XCTAssertThrowsError(try harness.runner.run(.specificBackup(harness.requestedBackup)))

        XCTAssertEqual(harness.executedSteps, [.rollbackStopRuntimeServices])
        XCTAssertEqual(harness.progressEvents.last?.step, .rollbackStopRuntimeServices)
        XCTAssertEqual(harness.progressEvents.last?.stepStatus, .failed)
        XCTAssertEqual(harness.statuses.last?.level, .recovering)
    }
}

private final class RollbackHarness {
    let requestedBackup = URL(fileURLWithPath: "/requested-backup")
    let preflight = RollbackPreflightContext(
        backup: URL(fileURLWithPath: "/backup"),
        backupRootfs: URL(fileURLWithPath: "/backup/rootfs-base.raw.gz"),
        backupVersion: URL(fileURLWithPath: "/backup/runtime-version.json"),
        restartPolicy: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: false,
            restartWatchdog: true
        )
    )

    var commandSeen: RuntimeRollbackCommand?
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedSteps: [RuntimeWorkflowStep] = []
    var logs: [String] = []
    var preflightError: Error?
    var stepError: Error?

    var runner: RuntimeRollbackRunner {
        RuntimeRollbackRunner(
            preparePreflight: { command in
                self.commandSeen = command
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
            writeStatus: { level, operation, message in
                self.statuses.append((level: level, operation: operation, message: message))
            },
            writeProgress: { event in
                self.progressEvents.append(event)
            },
            vmDiskPath: {
                "/runtime/vm-disk.img"
            },
            log: { message in
                self.logs.append(message)
            }
        )
    }
}

private enum TestRollbackError: Error {
    case preflight
    case step
}
