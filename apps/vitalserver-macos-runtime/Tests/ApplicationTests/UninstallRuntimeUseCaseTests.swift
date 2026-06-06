import Application
import Contracts
import Domain
import Foundation
import XCTest
import Errors

final class UninstallRuntimeUseCaseTests: XCTestCase {
    func testTransitionReturnsExplicitDecisionWithoutPersistingState() throws {
        let useCase = UninstallRuntimeUseCase()

        let decision = try useCase.transition(
            from: .notStarted,
            event: .start(clean: true),
            expectedCommands: []
        )

        XCTAssertEqual(decision.state, .started)
        XCTAssertEqual(decision.persistedState, .started)
        XCTAssertEqual(decision.message, "uninstall started")
        XCTAssertEqual(decision.blockers, [])
    }

    func testBlockedTransitionExpectsNoCommandsAndCarriesBlockers() throws {
        let useCase = UninstallRuntimeUseCase()

        let decision = try useCase.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(RuntimeUninstallReadinessInput(
                serviceStates: [.vm: .loaded],
                vmProcessState: .running(pid: 123)
            )),
            expectedCommandsWhenAllowed: [.removeFiles]
        )

        XCTAssertEqual(decision.commands, [])
        XCTAssertEqual(decision.state, .serviceStopBlocked)
        XCTAssertTrue(decision.blockers.contains("launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm"))
        XCTAssertTrue(decision.blockers.contains("vm-process-running:pid=123"))
    }

    func testUnexpectedCommandsFailExplicitly() throws {
        let useCase = UninstallRuntimeUseCase()
        let decision = RuntimeUninstallTransitionDecision(
            state: .started,
            persistedState: .started,
            commands: [.stopRuntimeServices],
            blockers: [],
            message: "unexpected"
        )

        XCTAssertThrowsError(try useCase.requireCommands([], in: decision)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "unexpected uninstall workflow commands state=started expected=[] actual=[Domain.RuntimeUninstallWorkflowCommand.stopRuntimeServices]"
            )
        }
    }

    func testPlansStartBackupPreserveAndRemovalFromExplicitCommandState() {
        let useCase = UninstallRuntimeUseCase()
        let productRoot = URL(fileURLWithPath: "/runtime")
        let defaultVitalFiles = URL(fileURLWithPath: "/Users/user/VitalFiles")

        let start = useCase.startPlan(clean: true, configuredDirectoryReadFailure: "permission denied")
        let preserve = useCase.preservePlan(
            productRoot: productRoot,
            defaultVitalFilesDirectory: defaultVitalFiles,
            externalVitalFilesDirectory: nil,
            configuredVitalFilesDirectoryReadFailure: "permission denied"
        )
        let removal = useCase.removalPlan(
            clean: true,
            managerApp: URL(fileURLWithPath: "/Applications/VitalServer.app"),
            productRoot: productRoot,
            externalVitalFilesDirectory: nil,
            configuredVitalFilesDirectoryReadFailure: "permission denied"
        )

        XCTAssertEqual(start.startedLogMessage, "uninstall started clean=true")
        XCTAssertEqual(start.configuredDirectoryReadFailureLogMessage, "configured vital files directory unavailable reason=permission denied")
        XCTAssertFalse(useCase.shouldCreateRedisBackup(clean: true))
        XCTAssertTrue(useCase.shouldCreateRedisBackup(clean: false))
        XCTAssertEqual(preserve.candidates.map(\.token), ["logs", "backups", "redis-backups", "vital-files"])
        XCTAssertEqual(
            preserve.configuredDirectoryReadFailureLogMessage,
            "preserving default vital files directory because configured external directory is unavailable reason=permission denied"
        )
        XCTAssertEqual(removal.targets, [
            URL(fileURLWithPath: "/Applications/VitalServer.app"),
            productRoot,
        ])
        XCTAssertEqual(
            removal.skippedExternalDirectoryLogMessage,
            "skipping external vital files directory cleanup because configured path is unavailable reason=permission denied"
        )
    }

    func testPreservePlanKeepsExternalVitalFilesDirectoryOwnedExternally() {
        let useCase = UninstallRuntimeUseCase()
        let externalVitalFiles = URL(fileURLWithPath: "/Volumes/Data/VitalFiles")

        let plan = useCase.preservePlan(
            productRoot: URL(fileURLWithPath: "/runtime"),
            defaultVitalFilesDirectory: URL(fileURLWithPath: "/Users/user/VitalFiles"),
            externalVitalFilesDirectory: externalVitalFiles,
            configuredVitalFilesDirectoryReadFailure: nil
        )

        XCTAssertEqual(plan.candidates.map(\.token), ["logs", "backups", "redis-backups"])
        XCTAssertEqual(plan.externalDirectoryLogMessage, "preserved external vital files directory=/Volumes/Data/VitalFiles")
        XCTAssertNil(plan.configuredDirectoryReadFailureLogMessage)
    }

    func testFileRemovalBlockersPreservePrimaryAndRestoreFailures() {
        let useCase = UninstallRuntimeUseCase()

        XCTAssertEqual(
            useCase.fileRemovalBlockers(
                removalFailureReason: "permission denied",
                preservedRestoreFailureReason: "restore failed"
            ),
            [
                "file-removal-failed:reason=permission denied",
                "restore-preserved-user-data-failed:reason=restore failed",
            ]
        )
    }

    func testReceiptDecisionAndFailureReasonUseExplicitObservedState() {
        let useCase = UninstallRuntimeUseCase()
        let observed = useCase.packageReceiptStateMap([
            .absent(identifier: "ai.tirosh.absent"),
            .present(identifier: "ai.tirosh.present"),
            .unknown("mystery"),
        ])

        XCTAssertEqual(
            useCase.receiptForgetDecision(identifier: "ai.tirosh.absent", observedReceiptStates: observed),
            .skip(logMessage: "package receipt already absent identifier=ai.tirosh.absent")
        )
        XCTAssertEqual(
            useCase.receiptForgetDecision(identifier: "ai.tirosh.present", observedReceiptStates: observed),
            .forget(logMessage: "forget package receipt identifier=ai.tirosh.present")
        )
        XCTAssertNil(observed["mystery"])
        XCTAssertEqual(
            useCase.processFailureReason(RuntimeProcessResult(exitCode: 1, stdout: "ignored", stderr: "permission denied\n")),
            "exitCode=1 stderr=permission denied"
        )
        XCTAssertEqual(
            useCase.processFailureReason(RuntimeProcessResult(exitCode: 2, stdout: "not found\n", stderr: "")),
            "exitCode=2 stdout=not found"
        )
        XCTAssertEqual(
            useCase.packageReceiptForgetFailureMessage(identifier: "pkg", reason: "exitCode=1"),
            "package receipt forget failed identifier=pkg exitCode=1"
        )
    }

    func testWorkflowMessagesComeFromUseCase() {
        let useCase = UninstallRuntimeUseCase()

        XCTAssertEqual(useCase.stepLogMessage(step: .removePlists, status: .started), "step=remove-plists status=started")
        XCTAssertEqual(useCase.stepLogMessage(step: .createRedisBackup, status: .completed), "step=create-redis-backup status=completed")
        XCTAssertEqual(
            useCase.preserveRootDirectory(
                temporaryDirectory: URL(fileURLWithPath: "/tmp"),
                uniqueID: "id-1"
            ),
            URL(fileURLWithPath: "/tmp/tirosh-vitalserver-uninstall-id-1")
        )
        XCTAssertEqual(
            useCase.redisBackupAbortLogMessage(reason: "backup failed"),
            "standard uninstall aborted because Redis backup did not complete error=backup failed"
        )
        XCTAssertEqual(useCase.restoringPreservedUserDataAfterFailureLogMessage(), "restoring preserved user data after uninstall failure")
        XCTAssertEqual(
            useCase.preservedUserDataRestoreFailedLogMessage(reason: "restore failed"),
            "preserved user data restore failed error=restore failed"
        )
        XCTAssertEqual(useCase.fileRemovalBlockedMessage(), "file removal blocked")
        XCTAssertEqual(useCase.preservedSourceLogMessage(path: "/product/logs"), "preserved source=/product/logs")
        XCTAssertEqual(useCase.restoredPreservedLogMessage(path: "/product/logs"), "restored preserved=/product/logs")
        XCTAssertEqual(useCase.unsafeRemovalTargetFailureMessage(path: "/"), "refusing unsafe removal target=/")
        XCTAssertEqual(useCase.removalIncompleteFailureMessage(path: "/product"), "removal incomplete target=/product")
        XCTAssertEqual(useCase.removalDiagnosticTargetLogMessage(path: "/product"), "removal diagnostic target=/product")
        XCTAssertEqual(useCase.removalDiagnosticResidualLogMessage(path: "/product/file"), "removal diagnostic residual path=/product/file")
        XCTAssertEqual(
            useCase.removalDiagnosticContentsReadFailedLogMessage(path: "/product", reason: "denied"),
            "removal diagnostic contents read failed target=/product error=denied"
        )
        XCTAssertEqual(useCase.removalDiagnosticOpenFileLogMessage(line: "proc file"), "removal diagnostic open file proc file")
        XCTAssertEqual(useCase.removalDiagnosticOpenFileStderrLogMessage(stderr: "lsof failed"), "removal diagnostic lsof stderr=lsof failed")
        XCTAssertEqual(
            useCase.packageReceiptVerificationFailedMessage(blockers: ["receipt-present"]),
            "package receipt forget verification failed blockers=receipt-present"
        )
        XCTAssertEqual(
            useCase.runtimeStopBlockedFailureMessage(blockers: ["vm-running"]),
            "runtime stop state blocked blockers=vm-running"
        )
        XCTAssertEqual(
            useCase.cleanupArtifactsRemainFailureMessage(blockers: ["artifact-present"]),
            "runtime cleanup artifacts remain blockers=artifact-present"
        )
        XCTAssertEqual(useCase.completedLogMessage(), "uninstall completed")
    }
}
