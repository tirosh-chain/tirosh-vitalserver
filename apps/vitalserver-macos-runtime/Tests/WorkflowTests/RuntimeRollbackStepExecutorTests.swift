import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest

final class RuntimeRollbackStepExecutorTests: XCTestCase {
    func testExecutePassesPlannerOutputToExecutionPortWithExplicitContext() throws {
        let backup = URL(fileURLWithPath: "/backups/before-1.2.3")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: false)
        )
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let runtimeVersion = URL(fileURLWithPath: "/runtime/runtime-version.json")
        let managerAppPath = URL(fileURLWithPath: "/Applications/VitalServer Manager.app")
        let nginxDirectory = URL(fileURLWithPath: "/product/nginx")
        let deployDirectory = URL(fileURLWithPath: "/product/deploy")
        let planned = RollbackRuntimeStepExecutionPlan.restoreRootfsBase(
            source: backup.appendingPathComponent(rootfsBaseName),
            destination: rootfsBase
        )
        var plannerCalls: [(RuntimeWorkflowStep, RuntimeRollbackStepExecutionContext)] = []
        var executedPlans: [RollbackRuntimeStepExecutionPlan] = []
        let executor = RuntimeRollbackStepExecutor(
            planStepExecution: { step, _, context in
                plannerCalls.append((step, context))
                return planned
            },
            executeStepPlan: { plan in
                executedPlans.append(plan)
            }
        )

        try executor.execute(
            .rollbackRestoreRootfsBase,
            preflight: preflight,
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: managerAppPath,
            nginxDirectory: nginxDirectory,
            deployDirectory: deployDirectory
        )

        XCTAssertEqual(plannerCalls.map(\.0), [.rollbackRestoreRootfsBase])
        XCTAssertEqual(plannerCalls.first?.1.rootfsBase, rootfsBase)
        XCTAssertEqual(plannerCalls.first?.1.runtimeVersion, runtimeVersion)
        XCTAssertEqual(plannerCalls.first?.1.managerAppPath, managerAppPath)
        XCTAssertEqual(plannerCalls.first?.1.nginxDirectory, nginxDirectory)
        XCTAssertEqual(plannerCalls.first?.1.deployDirectory, deployDirectory)
        XCTAssertEqual(executedPlans, [planned])
    }

    func testExecuteDelegatesUnsupportedPlanWithoutWorkflowInterpretation() throws {
        let backup = URL(fileURLWithPath: "/backup")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: stoppedPolicy
        )
        var executedPlans: [RollbackRuntimeStepExecutionPlan] = []
        let executor = RuntimeRollbackStepExecutor(
            planStepExecution: { step, _, _ in
                .unsupported(failureMessage: "unsupported rollback step \(step.rawValue)")
            },
            executeStepPlan: { executedPlans.append($0) }
        )

        try executor.execute(
            .stopRuntimeServices,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )

        XCTAssertEqual(executedPlans, [
            .unsupported(failureMessage: "unsupported rollback step stop-runtime-services"),
        ])
    }

    func testExecutePropagatesPlanExecutionFailure() {
        let backup = URL(fileURLWithPath: "/backup")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: stoppedPolicy
        )
        let executor = RuntimeRollbackStepExecutor(
            planStepExecution: { _, _, _ in .stopRuntimeServices },
            executeStepPlan: { _ in throw TestRollbackStepExecutorError.executionFailed }
        )

        XCTAssertThrowsError(try executor.execute(
            .rollbackStopRuntimeServices,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )) { error in
            XCTAssertEqual(error as? TestRollbackStepExecutorError, .executionFailed)
        }
    }
}

private let rootfsBaseName = "rootfs-base.raw.gz"
private let runtimeVersionName = "runtime-version.json"
private let stoppedPolicy = RuntimeServiceRestartPolicy(
    restartVM: false,
    restartGuestLogSync: false,
    restartProxy: false,
    restartWatchdog: false
)

private enum TestRollbackStepExecutorError: Error, Equatable {
    case executionFailed
}
