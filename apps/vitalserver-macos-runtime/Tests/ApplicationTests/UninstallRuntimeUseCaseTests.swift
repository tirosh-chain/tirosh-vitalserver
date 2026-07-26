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

    func testPlansStartBackupPreserveAndRemovalFromExplicitOwnedPaths() {
        let useCase = UninstallRuntimeUseCase()
        let productRoot = URL(fileURLWithPath: "/runtime")
        let legacyDefault = productRoot.appendingPathComponent("vm/data/vital-files")
        let sharedDefault = URL(fileURLWithPath: "/Users/Shared/VitalServerHelper/vital-files")
        let vitalFilesDirectories = UninstallRuntimeVitalFilesDirectories(
            revision: 8,
            appliedRevision: 7,
            directories: [
                UninstallRuntimeVitalFilesDirectory(
                    directory: legacyDefault,
                    ownership: .legacyManagedDefault,
                    sources: [.applied(revision: 7)]
                ),
                UninstallRuntimeVitalFilesDirectory(
                    directory: sharedDefault,
                    ownership: .sharedManagedDefault,
                    sources: [.desired(revision: 8)]
                ),
            ]
        )

        let start = useCase.startPlan(clean: true, forceClean: false)
        let preserve = useCase.preservePlan(
            productRoot: productRoot,
            legacyManagedDefaultVitalFilesDirectory: legacyDefault,
            vitalFilesOwnership: .resolved(vitalFilesDirectories)
        )
        let removal = useCase.removalPlan(
            clean: true,
            managerApp: URL(fileURLWithPath: "/Applications/VitalServer.app"),
            legacyManagedDefaultVitalFilesDirectory: legacyDefault,
            sharedManagedDefaultVitalFilesDirectory: sharedDefault,
            retainedDataRoot: URL(fileURLWithPath: "/runtime-retained-uninstall-data"),
            vitalFilesOwnership: .resolved(vitalFilesDirectories)
        )

        XCTAssertEqual(start.startedLogMessage, "uninstall started clean=true forceClean=false")
        XCTAssertFalse(useCase.shouldCreateVitalServerBackup(clean: true))
        XCTAssertTrue(useCase.shouldCreateVitalServerBackup(clean: false))
        XCTAssertEqual(
            preserve.candidates.map(\.token),
            ["logs", "backups", "redis-backups", "legacy-vital-files"]
        )
        XCTAssertEqual(
            preserve.vitalFilesDirectoryLogMessages,
            ["preserved shared managed default vital files directory in place path=/Users/Shared/VitalServerHelper/vital-files"]
        )
        XCTAssertEqual(removal.targets, [
            URL(fileURLWithPath: "/Applications/VitalServer.app"),
            legacyDefault,
            sharedDefault,
            URL(fileURLWithPath: "/runtime-retained-uninstall-data"),
        ])
        XCTAssertEqual(removal.preservedExternalDirectoryLogMessages, [])
    }

    func testRelocatedProductRootUsesSiblingTombstone() {
        let useCase = UninstallRuntimeUseCase()

        XCTAssertEqual(
            useCase.relocatedProductRoot(
                productRoot: URL(fileURLWithPath: "/Library/Application Support/VitalServerHelper"),
                uniqueID: "operation-1"
            ).path,
            "/Library/Application Support/.VitalServerHelper.uninstall-operation-1"
        )
    }

    func testPreservePlanKeepsExternalVitalFilesDirectoryOwnedExternally() {
        let useCase = UninstallRuntimeUseCase()
        let externalVitalFiles = URL(fileURLWithPath: "/Volumes/Data/VitalFiles")
        let directories = UninstallRuntimeVitalFilesDirectories(
            revision: 4,
            appliedRevision: nil,
            directories: [
                UninstallRuntimeVitalFilesDirectory(
                    directory: externalVitalFiles,
                    ownership: .external,
                    sources: [.desired(revision: 4)]
                ),
            ]
        )

        let plan = useCase.preservePlan(
            productRoot: URL(fileURLWithPath: "/runtime"),
            legacyManagedDefaultVitalFilesDirectory: URL(
                fileURLWithPath: "/runtime/vm/data/vital-files"
            ),
            vitalFilesOwnership: .resolved(directories)
        )

        XCTAssertEqual(
            plan.candidates.map(\.token),
            ["logs", "backups", "redis-backups", "legacy-vital-files"]
        )
        XCTAssertEqual(
            plan.vitalFilesDirectoryLogMessages,
            ["preserved external vital files directory in place path=/Volumes/Data/VitalFiles"]
        )
    }

    func testCleanRemovalPlanNeverOwnsConfiguredExternalVitalFilesDirectory() {
        let useCase = UninstallRuntimeUseCase()
        let managerApp = URL(fileURLWithPath: "/Applications/VitalServer.app")
        let externalVitalFiles = URL(fileURLWithPath: "/Volumes/Data/VitalFiles")
        let legacyDefault = URL(fileURLWithPath: "/runtime/vm/data/vital-files")
        let sharedDefault = URL(fileURLWithPath: "/Users/Shared/VitalServerHelper/vital-files")
        let directories = UninstallRuntimeVitalFilesDirectories(
            revision: 4,
            appliedRevision: nil,
            directories: [
                UninstallRuntimeVitalFilesDirectory(
                    directory: externalVitalFiles,
                    ownership: .external,
                    sources: [.desired(revision: 4)]
                ),
            ]
        )

        let plan = useCase.removalPlan(
            clean: true,
            managerApp: managerApp,
            legacyManagedDefaultVitalFilesDirectory: legacyDefault,
            sharedManagedDefaultVitalFilesDirectory: sharedDefault,
            retainedDataRoot: URL(fileURLWithPath: "/runtime-retained-uninstall-data"),
            vitalFilesOwnership: .resolved(directories)
        )

        XCTAssertEqual(plan.targets, [
            managerApp,
            legacyDefault,
            sharedDefault,
            URL(fileURLWithPath: "/runtime-retained-uninstall-data"),
        ])
        XCTAssertEqual(
            plan.preservedExternalDirectoryLogMessages,
            ["preserved configured external vital files directory path=/Volumes/Data/VitalFiles reason=no-product-owned-removal-contract"]
        )
    }

    func testResolvesDesiredAndAppliedPathsAndDeduplicatesStandardizedPath() {
        let useCase = UninstallRuntimeUseCase()
        let resolution = useCase.resolveVitalFilesDirectories(
            read: .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                revision: 9,
                appliedRevision: 8,
                directories: [
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .desired(revision: 9),
                        directory: URL(fileURLWithPath: "/Volumes/Data/./VitalFiles")
                    ),
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .applied(revision: 8),
                        directory: URL(fileURLWithPath: "/Volumes/Data/VitalFiles")
                    ),
                ]
            )),
            productRoot: URL(fileURLWithPath: "/product"),
            legacyManagedDefault: URL(fileURLWithPath: "/product/vm/data/vital-files"),
            sharedManagedDefault: URL(fileURLWithPath: "/Users/Shared/VitalServerHelper/vital-files"),
            retainedDataRoot: URL(fileURLWithPath: "/retained")
        )

        XCTAssertEqual(
            resolution,
            .available(UninstallRuntimeVitalFilesDirectories(
                revision: 9,
                appliedRevision: 8,
                directories: [
                    UninstallRuntimeVitalFilesDirectory(
                        directory: URL(fileURLWithPath: "/Volumes/Data/VitalFiles"),
                        ownership: .external,
                        sources: [.desired(revision: 9), .applied(revision: 8)]
                    ),
                ]
            ))
        )
    }

    func testRejectsConfiguredPathThatOverlapsManagedBoundary() {
        let useCase = UninstallRuntimeUseCase()
        let resolution = useCase.resolveVitalFilesDirectories(
            read: .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                revision: 9,
                appliedRevision: nil,
                directories: [
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .desired(revision: 9),
                        directory: URL(fileURLWithPath: "/product/vm/data")
                    ),
                ]
            )),
            productRoot: URL(fileURLWithPath: "/product"),
            legacyManagedDefault: URL(fileURLWithPath: "/product/vm/data/vital-files"),
            sharedManagedDefault: URL(fileURLWithPath: "/Users/Shared/VitalServerHelper/vital-files"),
            retainedDataRoot: URL(fileURLWithPath: "/retained")
        )

        XCTAssertEqual(
            resolution,
            .unavailable(.ambiguousOverlap(
                path: "/product/vm/data",
                boundary: "/product",
                sources: [.desired(revision: 9)]
            ))
        )
    }

    func testRejectsManagedBoundaryPathThatDiffersOnlyByCase() {
        let useCase = UninstallRuntimeUseCase()
        let resolution = useCase.resolveVitalFilesDirectories(
            read: .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                revision: 9,
                appliedRevision: nil,
                directories: [
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .desired(revision: 9),
                        directory: URL(
                            fileURLWithPath: "/users/shared/vitalserverhelper/VITAL-FILES"
                        )
                    ),
                ]
            )),
            productRoot: URL(fileURLWithPath: "/product"),
            legacyManagedDefault: URL(fileURLWithPath: "/product/vm/data/vital-files"),
            sharedManagedDefault: URL(
                fileURLWithPath: "/Users/Shared/VitalServerHelper/vital-files"
            ),
            retainedDataRoot: URL(fileURLWithPath: "/retained")
        )

        XCTAssertEqual(
            resolution,
            .unavailable(.ambiguousOverlap(
                path: "/users/shared/vitalserverhelper/VITAL-FILES",
                boundary: "/Users/Shared/VitalServerHelper/vital-files",
                sources: [.desired(revision: 9)]
            ))
        )
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
        XCTAssertEqual(useCase.stepLogMessage(step: .createVitalServerBackup, status: .completed), "step=create-vitalserver-backup status=completed")
        XCTAssertEqual(
            useCase.preserveRootDirectory(
                retainedDataRoot: URL(fileURLWithPath: "/retained-uninstall-data"),
                uniqueID: "id-1"
            ),
            URL(fileURLWithPath: "/retained-uninstall-data/tirosh-vitalserver-uninstall-id-1")
        )
        XCTAssertNotEqual(
            useCase.preserveRootDirectory(
                retainedDataRoot: URL(fileURLWithPath: "/retained-uninstall-data"),
                uniqueID: "id-1"
            ),
            useCase.preserveRootDirectory(
                retainedDataRoot: URL(fileURLWithPath: "/retained-uninstall-data"),
                uniqueID: "id-2"
            )
        )
        XCTAssertEqual(
            useCase.retainedDataDirectoryAlreadyPresentMessage(
                path: "/retained-uninstall-data/tirosh-vitalserver-uninstall-id-1"
            ),
            "refusing to replace existing retained uninstall data path=/retained-uninstall-data/tirosh-vitalserver-uninstall-id-1"
        )
        XCTAssertEqual(
            useCase.retainedUserDataLogMessage(
                path: "/retained-uninstall-data/tirosh-vitalserver-uninstall-id-1"
            ),
            "retained standard uninstall data path=/retained-uninstall-data/tirosh-vitalserver-uninstall-id-1 owner=uninstall-retained-data"
        )
        XCTAssertEqual(
            useCase.vitalServerBackupAbortLogMessage(reason: "backup failed"),
            "standard uninstall aborted because VitalServer backup did not complete error=backup failed"
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
            useCase.removalDiagnosticOpenFilePlan(
                executable: "/usr/sbin/lsof",
                target: URL(fileURLWithPath: "/runtime/product")
            ),
            UninstallRuntimeProcessPlan(
                executable: "/usr/sbin/lsof",
                arguments: ["+D", "/runtime/product"]
            )
        )
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
