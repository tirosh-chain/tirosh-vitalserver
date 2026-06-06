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
}
