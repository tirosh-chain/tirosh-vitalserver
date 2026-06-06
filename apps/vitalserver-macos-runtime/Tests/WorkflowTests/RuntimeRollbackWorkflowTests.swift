import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RollbackRuntimeWorkflowTests: XCTestCase {
    func testRunExecutesRollbackPlanAndWritesHealthyStatus() throws {
        let harness = RollbackHarness()

        try harness.useCase.run(
            .specificBackup(harness.requestedBackup),
            context: harness.executionContext,
            operations: harness.operations
        )

        XCTAssertEqual(harness.selectionSeen, .specificBackup(harness.requestedBackup))
        XCTAssertEqual(harness.effects, [
            "stop",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
            "replace:runtime-version.json:runtime-version.json",
            "restore:app-bundle:VitalServer Manager.app",
            "restore:nginx-bundle:nginx",
            "restore:guest-deploy:deploy",
            "tools:runtime-tools",
            "start:true:false:true",
            "wait:true:false:true",
        ])
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
        harness.backupDirectoryExists = false

        XCTAssertThrowsError(try harness.useCase.run(
            .specificBackup(harness.requestedBackup),
            context: harness.executionContext,
            operations: harness.operations
        )) { error in
            XCTAssertEqual(
                error as? RollbackRuntimeUseCaseError,
                .operationFailed("missing file: /requested-backup")
            )
        }

        XCTAssertTrue(harness.effects.isEmpty)
        XCTAssertTrue(harness.statuses.isEmpty)
    }

    func testRunPublishesFailedProgressWhenStepFails() {
        let harness = RollbackHarness()
        harness.stepErrorAt = .rollbackRestoreRootfsBase

        XCTAssertThrowsError(try harness.useCase.run(
            .specificBackup(harness.requestedBackup),
            context: harness.executionContext,
            operations: harness.operations
        ))

        XCTAssertEqual(harness.effects, [
            "stop",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
        ])
        XCTAssertEqual(harness.progressEvents.last?.step, .rollbackRestoreRootfsBase)
        XCTAssertEqual(harness.progressEvents.last?.stepStatus, .failed)
        XCTAssertEqual(harness.statuses.last?.level, .recovering)
    }

    func testPrepareUsesRequestedBackupAndBuildsContextFromExplicitObservations() throws {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let backupRootfs = requestedBackup.appendingPathComponent(RuntimeFileNames.rootfsBase)
        var events: [String] = []

        let operations = operationsForPreflight(
            resolveBackupSelection: { selection in
                events.append("selection:\(selectionLabel(selection))")
                switch selection {
                case .specificBackup(let backup):
                    return backup
                case .latestBackup:
                    XCTFail("requested backup should not resolve latest backup")
                    return URL(fileURLWithPath: "/unused")
                }
            },
            observeBackupDirectory: { backup in
                events.append("directory:\(backup.path)")
                return RollbackRuntimeBackupDirectoryObservation(
                    backup: backup,
                    directoryExists: backup == requestedBackup
                )
            },
            loadBackupManifest: { backup in
                events.append("manifest:\(backup.path)")
                return backupManifest(rootfsBase: RuntimeFileNames.rootfsBase)
            },
            observeBackupRootfs: { plan in
                events.append("file:\(plan.backupRootfs?.path ?? "none")")
                return RollbackRuntimeBackupRootfsObservation(
                    backupPlan: plan,
                    backupRootfsExists: plan.backupRootfs == backupRootfs
                )
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
            },
            log: { _ in events.append("log") }
        )

        let context = try RollbackRuntimeWorkflow().preparePreflight(.specificBackup(requestedBackup), operations: operations)

        XCTAssertEqual(context.backup, requestedBackup)
        XCTAssertEqual(context.backupRootfs, backupRootfs)
        XCTAssertEqual(context.backupVersion, requestedBackup.appendingPathComponent(RuntimeFileNames.runtimeVersion))
        XCTAssertTrue(context.restoresRootfsBase)
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: true
        ))
        XCTAssertEqual(events, [
            "selection:specific:/product/backups/backup-1",
            "directory:/product/backups/backup-1",
            "manifest:/product/backups/backup-1",
            "file:/product/backups/backup-1/rootfs-base.raw.gz",
            "policy",
            "log",
        ])
    }

    func testPrepareFailsBeforeManifestWhenBackupDirectoryIsMissing() {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/missing")
        let operations = operationsForPreflight(
            resolveBackupSelection: { _ in requestedBackup },
            observeBackupDirectory: { backup in
                RollbackRuntimeBackupDirectoryObservation(backup: backup, directoryExists: false)
            },
            loadBackupManifest: { _ in
                XCTFail("missing backup directory should stop before manifest load")
                return backupManifest(rootfsBase: RuntimeFileNames.rootfsBase)
            },
            observeBackupRootfs: { plan in
                XCTFail("missing backup directory should stop before rootfs observation")
                return RollbackRuntimeBackupRootfsObservation(backupPlan: plan, backupRootfsExists: nil)
            },
            serviceRestartPolicy: {
                XCTFail("missing backup directory should stop before service policy")
                return stoppedPolicy
            },
            log: { _ in XCTFail("missing backup directory should stop before logging") }
        )

        XCTAssertThrowsError(try RollbackRuntimeWorkflow().preparePreflight(
            .specificBackup(requestedBackup),
            operations: operations
        )) { error in
            XCTAssertEqual(error as? RollbackRuntimeUseCaseError, .operationFailed("missing file: \(requestedBackup.path)"))
        }
    }

    func testPrepareFailsBeforePolicyWhenBackupRootfsIsMissing() {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let missingRootfs = requestedBackup.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let operations = operationsForPreflight(
            resolveBackupSelection: { _ in requestedBackup },
            observeBackupDirectory: { backup in
                RollbackRuntimeBackupDirectoryObservation(backup: backup, directoryExists: true)
            },
            loadBackupManifest: { _ in backupManifest(rootfsBase: RuntimeFileNames.rootfsBase) },
            observeBackupRootfs: { plan in
                RollbackRuntimeBackupRootfsObservation(backupPlan: plan, backupRootfsExists: false)
            },
            serviceRestartPolicy: {
                XCTFail("missing rootfs should stop before service policy")
                return stoppedPolicy
            },
            log: { _ in XCTFail("missing rootfs should stop before logging") }
        )

        XCTAssertThrowsError(try RollbackRuntimeWorkflow().preparePreflight(
            .specificBackup(requestedBackup),
            operations: operations
        )) { error in
            XCTAssertEqual(error as? RollbackRuntimeUseCaseError, .operationFailed("missing file: \(missingRootfs.path)"))
        }
    }

    func testExecuteStepPassesPlannerOutputToExecutionPortWithExplicitContext() throws {
        let backup = URL(fileURLWithPath: "/backups/before-1.2.3")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(RuntimeFileNames.rootfsBase),
            backupVersion: backup.appendingPathComponent(RuntimeFileNames.runtimeVersion),
            restoresRootfsBase: true,
            restartPolicy: stoppedPolicy
        )
        let stepContext = RollbackRuntimeStepExecutionContext(
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )
        var observedRequiredInputs: [RollbackRuntimeStepRequiredInput] = []
        var replacedFiles: [(source: URL, destination: URL)] = []
        let operations = operationsForStep(
            observeStepRequiredInput: { _, _, requiredInput in
                observedRequiredInputs.append(requiredInput)
                return RollbackRuntimeStepRequiredInputObservation(
                    requiredInput: requiredInput,
                    backupVersionExists: true
                )
            },
            replaceFile: { source, destination in
                replacedFiles.append((source, destination))
            }
        )

        try RollbackRuntimeWorkflow().executeStep(
            .rollbackRestoreRuntimeVersion,
            preflight: preflight,
            context: stepContext,
            operations: operations
        )

        XCTAssertEqual(observedRequiredInputs, [.backupVersionExists(preflight.backupVersion)])
        XCTAssertEqual(replacedFiles.map(\.source), [preflight.backupVersion])
        XCTAssertEqual(replacedFiles.map(\.destination), [stepContext.runtimeVersion])
    }

    private func operationsForPreflight(
        resolveBackupSelection: @escaping (RollbackRuntimeBackupSelection) throws -> URL,
        observeBackupDirectory: @escaping (URL) -> RollbackRuntimeBackupDirectoryObservation,
        loadBackupManifest: @escaping (URL) throws -> BackupManifest,
        observeBackupRootfs: @escaping (RollbackRuntimeBackupPlan) -> RollbackRuntimeBackupRootfsObservation,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        log: @escaping (String) -> Void
    ) -> RollbackRuntimeOperations {
        RollbackRuntimeOperations(
            resolveBackupSelection: resolveBackupSelection,
            observeBackupDirectory: observeBackupDirectory,
            loadBackupManifest: loadBackupManifest,
            observeBackupRootfs: observeBackupRootfs,
            serviceRestartPolicy: serviceRestartPolicy,
            observeStepRequiredInput: { _, _, requiredInput in
                RollbackRuntimeStepRequiredInputObservation(requiredInput: requiredInput, backupVersionExists: false)
            },
            stopRuntimeServices: {},
            replaceFile: { _, _ in },
            writeRuntimeVersion: { _, _ in },
            restoreBackupPathIfExists: { _, _ in },
            restoreRuntimeToolsIfExists: { _ in },
            startRuntimeServices: { _ in },
            waitForHealth: { _ in },
            writeStatus: { _, _, _ in },
            writeProgress: { _ in },
            describeError: { _ in "progress write failed" },
            log: log
        )
    }

    private func operationsForStep(
        observeStepRequiredInput: @escaping (
            RuntimeWorkflowStep,
            RollbackPreflightContext,
            RollbackRuntimeStepRequiredInput
        ) -> RollbackRuntimeStepRequiredInputObservation,
        replaceFile: @escaping (URL, URL) throws -> Void
    ) -> RollbackRuntimeOperations {
        RollbackRuntimeOperations(
            resolveBackupSelection: { _ in URL(fileURLWithPath: "/backup") },
            observeBackupDirectory: { backup in
                RollbackRuntimeBackupDirectoryObservation(backup: backup, directoryExists: true)
            },
            loadBackupManifest: { _ in backupManifest(rootfsBase: RuntimeFileNames.rootfsBase) },
            observeBackupRootfs: { plan in
                RollbackRuntimeBackupRootfsObservation(backupPlan: plan, backupRootfsExists: true)
            },
            serviceRestartPolicy: { stoppedPolicy },
            observeStepRequiredInput: observeStepRequiredInput,
            stopRuntimeServices: {},
            replaceFile: replaceFile,
            writeRuntimeVersion: { _, _ in },
            restoreBackupPathIfExists: { _, _ in },
            restoreRuntimeToolsIfExists: { _ in },
            startRuntimeServices: { _ in },
            waitForHealth: { _ in },
            writeStatus: { _, _, _ in },
            writeProgress: { _ in },
            describeError: { _ in "progress write failed" },
            log: { _ in }
        )
    }
}

private final class RollbackHarness {
    let useCase = RollbackRuntimeWorkflow()
    let requestedBackup = URL(fileURLWithPath: "/requested-backup")
    let backup = URL(fileURLWithPath: "/backup")
    let executionContext = RollbackRuntimeExecutionContext(
        rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
        runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
        vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.img"),
        managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
        nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
        deployDirectory: URL(fileURLWithPath: "/product/deploy")
    )

    var selectionSeen: RollbackRuntimeBackupSelection?
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var effects: [String] = []
    var logs: [String] = []
    var backupDirectoryExists = true
    var backupRootfsExists = true
    var stepErrorAt: RuntimeWorkflowStep?

    lazy var operations = RollbackRuntimeOperations(
        resolveBackupSelection: { [self] selection in
            selectionSeen = selection
            return backupDirectoryExists ? backup : requestedBackup
        },
        observeBackupDirectory: { [self] backup in
            RollbackRuntimeBackupDirectoryObservation(
                backup: backup,
                directoryExists: backupDirectoryExists
            )
        },
        loadBackupManifest: { _ in backupManifest(rootfsBase: RuntimeFileNames.rootfsBase) },
        observeBackupRootfs: { [self] plan in
            RollbackRuntimeBackupRootfsObservation(
                backupPlan: plan,
                backupRootfsExists: backupRootfsExists
            )
        },
        serviceRestartPolicy: {
            RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
        },
        observeStepRequiredInput: { _, _, requiredInput in
            RollbackRuntimeStepRequiredInputObservation(
                requiredInput: requiredInput,
                backupVersionExists: true
            )
        },
        stopRuntimeServices: { [self] in
            effects.append("stop")
            try throwIfStepShouldFail(.rollbackStopRuntimeServices)
        },
        replaceFile: { [self] source, destination in
            effects.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
            if destination == executionContext.rootfsBase {
                try throwIfStepShouldFail(.rollbackRestoreRootfsBase)
            } else if destination == executionContext.runtimeVersion {
                try throwIfStepShouldFail(.rollbackRestoreRuntimeVersion)
            }
        },
        writeRuntimeVersion: { [self] version, destinationDirectory in
            effects.append("version:\(version):\(destinationDirectory.lastPathComponent)")
            try throwIfStepShouldFail(.rollbackRestoreRuntimeVersion)
        },
        restoreBackupPathIfExists: { [self] source, destination in
            effects.append("restore:\(source.lastPathComponent):\(destination.lastPathComponent)")
            try throwIfStepShouldFail(.rollbackRestoreUpdateArtifacts)
        },
        restoreRuntimeToolsIfExists: { [self] source in
            effects.append("tools:\(source.lastPathComponent)")
            try throwIfStepShouldFail(.rollbackRestoreUpdateArtifacts)
        },
        startRuntimeServices: { [self] policy in
            effects.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            try throwIfStepShouldFail(.rollbackStartRuntimeServices)
        },
        waitForHealth: { [self] policy in
            effects.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            try throwIfStepShouldFail(.rollbackWaitRuntimeHealth)
        },
        writeStatus: { [self] level, operation, message in
            statuses.append((level: level, operation: operation, message: message))
        },
        writeProgress: { [self] event in
            progressEvents.append(event)
        },
        describeError: { _ in
            "progress write failed"
        },
        log: { [self] message in
            logs.append(message)
        }
    )

    private func throwIfStepShouldFail(_ step: RuntimeWorkflowStep) throws {
        if stepErrorAt == step {
            throw TestRollbackUseCaseError.step
        }
    }
}

private let stoppedPolicy = RuntimeServiceRestartPolicy(
    restartVM: false,
    restartGuestLogSync: false,
    restartProxy: false,
    restartWatchdog: false
)

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

private func selectionLabel(_ selection: RollbackRuntimeBackupSelection) -> String {
    switch selection {
    case .latestBackup:
        return "latest"
    case .specificBackup(let backup):
        return "specific:\(backup.path)"
    }
}

private enum TestRollbackUseCaseError: Error {
    case step
}
