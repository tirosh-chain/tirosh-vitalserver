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
                    selectedBackup == backup
                        ? .loadManifest(selectedBackup)
                        : .failed(message: "missing file: \(selectedBackup.path)")
                },
                resolveBackupRootfs: { backupPlan in
                    backupPlan.backupRootfs == backupRootfs
                        ? .proceed(backupPlan)
                        : .failed(message: "missing file: \(backupPlan.backupRootfs?.path ?? "unknown")")
                },
                observeRequiredInput: { requiredInput in
                    switch requiredInput {
                    case .none:
                        return RollbackRuntimeStepRequiredInputObservation(
                            requiredInput: requiredInput,
                            backupVersionExists: false
                        )
                    case .backupVersionExists(let requiredBackupVersion):
                        return RollbackRuntimeStepRequiredInputObservation(
                            requiredInput: requiredInput,
                            backupVersionExists: requiredBackupVersion == backupVersion
                        )
                    }
                },
                loadBackupManifest: { url in
                    events.append("manifest:\(url.lastPathComponent)")
                    return backupManifest(rootfsBase: RuntimeFileNames.rootfsBase)
                },
                isLaunchdLoaded: { service in
                    events.append("loaded:\(serviceName(service))")
                    return service == .vm || service == .proxy
                },
                stopRuntimeServices: { events.append("stop") },
                startRuntimeServices: { policy in
                    events.append(
                        "start:\(policy.restartVM):\(policy.restartGuestLogSync):\(policy.restartProxy):\(policy.restartWatchdog)"
                    )
                },
                waitForHealth: { policy in
                    events.append(
                        "wait:\(policy.restartVM):\(policy.restartGuestLogSync):\(policy.restartProxy):\(policy.restartWatchdog)"
                    )
                },
                replaceFile: { source, destination in
                    events.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
                },
                writeRuntimeVersion: { version, bundle in
                    events.append("version:\(version):\(bundle.lastPathComponent)")
                },
                restoreBackupPathIfExists: { source, destination in
                    events.append("restore:\(source.lastPathComponent):\(destination.lastPathComponent)")
                },
                restoreRuntimeToolsIfExists: { source in
                    events.append("tools:\(source.lastPathComponent)")
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
            "restore:app-bundle:VitalServer Manager.app",
            "restore:nginx-bundle:nginx",
            "restore:guest-deploy:deploy",
            "tools:runtime-tools",
            "start:true:false:true:false",
            "wait:true:false:true:false",
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
                    selectedBackup == backup
                        ? .loadManifest(selectedBackup)
                        : .failed(message: "missing file: \(selectedBackup.path)")
                },
                resolveBackupRootfs: { backupPlan in
                    XCTFail("missing manifest should stop before rootfs observation")
                    return .proceed(backupPlan)
                },
                observeRequiredInput: { requiredInput in
                    XCTFail("missing manifest should stop before rollback step input observation")
                    return RollbackRuntimeStepRequiredInputObservation(
                        requiredInput: requiredInput,
                        backupVersionExists: false
                    )
                },
                loadBackupManifest: { _ in
                    throw RuntimeBackupManifestLoaderError.missingFile(
                        path: backup.appendingPathComponent(RuntimeFileNames.backupManifest).path
                    )
                },
                isLaunchdLoaded: { _ in false },
                stopRuntimeServices: { stopped = true },
                startRuntimeServices: { _ in },
                waitForHealth: { _ in },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                restoreBackupPathIfExists: { _, _ in },
                restoreRuntimeToolsIfExists: { _ in },
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
