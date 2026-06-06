import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeRollbackWorkflowTests: XCTestCase {
    func testRollbackRunsPreflightPlanAndStepAdapters() throws {
        let backup = URL(fileURLWithPath: "/product/backups/before-1.2.3")
        let backupRootfs = backup.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let backupVersion = backup.appendingPathComponent(RuntimeFileNames.runtimeVersion)
        var events: [String] = []
        var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
        var progressEvents: [RuntimeStepExecutionEvent] = []

        let workflow = RuntimeRollbackWorkflow(
            context: context(),
            operations: RuntimeRollbackWorkflowOperations(
                resolveBackupSelection: { selection in
                    events.append("selection:\(selectionLabel(selection))")
                    switch selection {
                    case .specificBackup(let selectedBackup):
                        return selectedBackup
                    case .latestBackup:
                        throw TestError.unexpectedLatestBackup
                    }
                },
                resolveBackupDirectory: { selectedBackup in
                    try executeBackupDirectoryDecision(selectedBackup == backup
                        ? .loadManifest(selectedBackup)
                        : .failed(message: "missing file: \(selectedBackup.path)")
                    )
                },
                resolveBackupRootfs: { backupPlan in
                    try executeBackupRootfsDecision(backupPlan.backupRootfs == backupRootfs
                        ? .proceed(backupPlan)
                        : .failed(message: "missing file: \(backupPlan.backupRootfs?.path ?? "unknown")")
                    )
                },
                loadBackupManifest: { url in
                    events.append("manifest:\(url.lastPathComponent)")
                    return backupManifest(rootfsBase: RuntimeFileNames.rootfsBase)
                },
                isLaunchdLoaded: { service in
                    events.append("loaded:\(serviceName(service))")
                    return service == .vm || service == .proxy
                },
                planRollbackStepExecution: { step, preflight, stepContext in
                    UpdateRuntimeUseCase().rollbackStepExecutionPlan(
                        step: step,
                        preflight: preflight,
                        rootfsBase: stepContext.rootfsBase,
                        runtimeVersion: stepContext.runtimeVersion,
                        managerAppPath: stepContext.managerAppPath,
                        nginxDirectory: stepContext.nginxDirectory,
                        deployDirectory: stepContext.deployDirectory,
                        backupVersionExists: preflight.backupVersion == backupVersion
                    )
                },
                executeRollbackStepPlan: { plan in
                    events.append(rollbackPlanLabel(plan))
                },
                writeStatus: { level, operation, message in
                    statuses.append((level, operation, message))
                },
                writeProgress: { event in
                    progressEvents.append(event)
                },
                log: { _ in }
            )
        )

        try workflow.rollback(RuntimeRollbackCommand.specificBackup(backup))

        XCTAssertEqual(statuses.first?.level, .recovering)
        XCTAssertEqual(statuses.last?.level, .healthy)
        XCTAssertEqual(statuses.last?.message, "rollback completed")
        XCTAssertEqual(
            progressEvents.filter { $0.stepStatus == .started }.map(\.step),
            RuntimeOperationPlans.rollback.steps
        )
        XCTAssertEqual(
            progressEvents.filter { $0.stepStatus == .completed }.map(\.step),
            RuntimeOperationPlans.rollback.steps
        )
        XCTAssertEqual(events, [
            "selection:specific:/product/backups/before-1.2.3",
            "manifest:before-1.2.3",
            "loaded:vm",
            "loaded:guest-log-sync",
            "loaded:proxy",
            "loaded:watchdog",
            "stop",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
            "replace:runtime-version.json:runtime-version.json",
            "restore:app-bundle:VitalServer Manager.app|restore:nginx-bundle:nginx|restore:guest-deploy:deploy|tools:runtime-tools",
            "start:true:true:false",
            "wait:true:true:false",
        ])
    }

    func testRollbackFailsBeforeStepsWhenBackupManifestIsMissing() {
        let backup = URL(fileURLWithPath: "/product/backups/before-1.2.3")
        var stopped = false
        let workflow = RuntimeRollbackWorkflow(
            context: context(),
            operations: RuntimeRollbackWorkflowOperations(
                resolveBackupSelection: { selection in
                    switch selection {
                    case .specificBackup(let selectedBackup):
                        return selectedBackup
                    case .latestBackup:
                        throw TestError.unexpectedLatestBackup
                    }
                },
                resolveBackupDirectory: { selectedBackup in
                    try executeBackupDirectoryDecision(selectedBackup == backup
                        ? .loadManifest(selectedBackup)
                        : .failed(message: "missing file: \(selectedBackup.path)")
                    )
                },
                resolveBackupRootfs: { backupPlan in
                    XCTFail("missing manifest should stop before rootfs observation")
                    return backupPlan
                },
                loadBackupManifest: { _ in
                    throw RuntimeBackupManifestLoaderError.missingFile(
                        path: backup.appendingPathComponent(RuntimeFileNames.backupManifest).path
                    )
                },
                isLaunchdLoaded: { _ in false },
                planRollbackStepExecution: { _, _, _ in
                    XCTFail("missing manifest should stop before rollback step planning")
                    return .stopRuntimeServices
                },
                executeRollbackStepPlan: { _ in stopped = true },
                writeStatus: { _, _, _ in },
                writeProgress: { _ in },
                log: { _ in }
            )
        )

        XCTAssertThrowsError(try workflow.rollback(.specificBackup(backup))) { error in
            XCTAssertEqual(
                String(describing: error),
                "missing file: \(backup.appendingPathComponent(RuntimeFileNames.backupManifest).path)"
            )
        }
        XCTAssertFalse(stopped)
    }
}

private func serviceName(_ service: RuntimeManagedService) -> String {
    switch service {
    case .vm:
        return "vm"
    case .guestLogSync:
        return "guest-log-sync"
    case .proxy:
        return "proxy"
    case .watchdog:
        return "watchdog"
    case .sleepPrevention:
        return "sleep-prevention"
    }
}

private func context() -> RuntimeRollbackWorkflowContext {
    RuntimeRollbackWorkflowContext(
        rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
        runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
        vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.img"),
        managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
        nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
        deployDirectory: URL(fileURLWithPath: "/product/deploy")
    )
}

private func backupManifest(rootfsBase: String?) -> BackupManifest {
    BackupManifest(
        product: "ai.tirosh.vitalserver.helper",
        createdAt: "2026-05-31T00:00:00Z",
        reason: "before-1.2.3",
        rootfsBase: rootfsBase,
        vmDisk: "vm-disk.img",
        vmDiskPreserved: true
    )
}

private func executeBackupDirectoryDecision(
    _ decision: RollbackRuntimeBackupDirectoryDecision
) throws -> URL {
    switch decision {
    case .loadManifest(let backup):
        return backup
    case .failed(let message):
        throw RuntimeRollbackWorkflowError.operationFailed(message)
    }
}

private func executeBackupRootfsDecision(
    _ decision: RollbackRuntimeBackupRootfsDecision
) throws -> RollbackRuntimeBackupPlan {
    switch decision {
    case .proceed(let plan):
        return plan
    case .failed(let message):
        throw RuntimeRollbackWorkflowError.operationFailed(message)
    }
}

private func rollbackPlanLabel(_ plan: RollbackRuntimeStepExecutionPlan) -> String {
    switch plan {
    case .stopRuntimeServices:
        return "stop"
    case .restoreRootfsBase(let source, let destination):
        return "replace:\(source.lastPathComponent):\(destination.lastPathComponent)"
    case .restoreRuntimeVersion(let decision):
        switch decision {
        case .restoreBackupVersion(let source, let destination):
            return "replace:\(source.lastPathComponent):\(destination.lastPathComponent)"
        case .writeExplicitRollbackMarker(let version, let destinationDirectory):
            return "version:\(version):\(destinationDirectory.lastPathComponent)"
        }
    case .restoreUpdateArtifacts(let restorePlan):
        let directoryRestores = restorePlan.directoryRestores.map {
            "restore:\($0.backupPath.lastPathComponent):\($0.restoreDestination.lastPathComponent)"
        }
        return (directoryRestores + ["tools:\(restorePlan.runtimeToolsBackup.lastPathComponent)"]).joined(separator: "|")
    case .startRuntimeServices(let policy):
        return "start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)"
    case .waitRuntimeHealth(let policy):
        return "wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)"
    case .failed(let failureMessage):
        return "failed:\(failureMessage)"
    case .unsupported(let failureMessage):
        return "unsupported:\(failureMessage)"
    }
}

private enum TestError: Error {
    case unexpectedLatestBackup
}

private func selectionLabel(_ selection: RollbackRuntimeBackupSelection) -> String {
    switch selection {
    case .latestBackup:
        return "latest"
    case .specificBackup(let backup):
        return "specific:\(backup.path)"
    }
}
