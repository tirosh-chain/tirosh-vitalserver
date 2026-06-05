import Contracts
import Core
import XCTest

final class RuntimeUninstallTransitionPolicyTests: XCTestCase {
    func testStartPersistsStartedWithoutInferringNextCommand() throws {
        let cleanStart = try RuntimeUninstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start(clean: true)
        )

        XCTAssertEqual(cleanStart.state, .started)
        XCTAssertEqual(cleanStart.persistedState, .started)
        XCTAssertEqual(cleanStart.commands, [])
        XCTAssertEqual(cleanStart.message, "uninstall started")

        let standardStart = try RuntimeUninstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start(clean: false)
        )

        XCTAssertEqual(standardStart.state, .started)
        XCTAssertEqual(standardStart.persistedState, .started)
        XCTAssertEqual(standardStart.commands, [])
        XCTAssertEqual(standardStart.message, "uninstall started")
    }

    func testRedisBackupRequestAndCompletionAreExplicitTransitions() throws {
        let requested = try RuntimeUninstallTransitionPolicy.transition(
            from: .started,
            event: .redisBackupRequested
        )

        XCTAssertEqual(requested.state, .redisBackupRequested)
        XCTAssertEqual(requested.persistedState, .redisBackupRequested)
        XCTAssertEqual(requested.commands, [.createRedisBackup])
        XCTAssertEqual(requested.message, "redis backup requested")

        let completed = try RuntimeUninstallTransitionPolicy.transition(
            from: requested.state,
            event: .redisBackupSucceeded
        )

        XCTAssertEqual(completed.state, .redisBackupCompleted)
        XCTAssertEqual(completed.persistedState, .redisBackupCompleted)
        XCTAssertEqual(completed.commands, [])
        XCTAssertEqual(completed.message, "redis backup completed")
    }

    func testStopRequestMustFollowStartedOrCompletedBackupState() throws {
        let cleanStopRequest = try RuntimeUninstallTransitionPolicy.transition(
            from: .started,
            event: .stopServicesRequested
        )

        XCTAssertEqual(cleanStopRequest.state, .stopServicesRequested)
        XCTAssertEqual(cleanStopRequest.persistedState, .stopServicesRequested)
        XCTAssertEqual(cleanStopRequest.commands, [.stopRuntimeServices])

        let standardStopRequest = try RuntimeUninstallTransitionPolicy.transition(
            from: .redisBackupCompleted,
            event: .stopServicesRequested
        )

        XCTAssertEqual(standardStopRequest.state, .stopServicesRequested)
        XCTAssertEqual(standardStopRequest.persistedState, .stopServicesRequested)
        XCTAssertEqual(standardStopRequest.commands, [.stopRuntimeServices])

        XCTAssertThrowsError(
            try RuntimeUninstallTransitionPolicy.transition(
                from: .notStarted,
                event: .stopServicesRequested
            )
        ) { error in
            XCTAssertTrue(error is RuntimeUninstallTransitionError)
        }
    }

    func testStoppedStateMustBeExplicitBeforeFileRemovalCommand() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .pidFileMissing, serviceState: .loaded))
        )

        XCTAssertEqual(blocked.state, .serviceStopBlocked)
        XCTAssertEqual(blocked.persistedState, .serviceStopBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("vm-process-pid-file-missing"))

        let missingPidWithStoppedService = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .pidFileMissing))
        )

        XCTAssertEqual(missingPidWithStoppedService.state, .stoppedVerified)
        XCTAssertEqual(missingPidWithStoppedService.commands, [.removeFiles])
        XCTAssertTrue(missingPidWithStoppedService.blockers.isEmpty)

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .stopped))
        )

        XCTAssertEqual(allowed.state, .stoppedVerified)
        XCTAssertEqual(allowed.commands, [.removeFiles])
        XCTAssertTrue(allowed.blockers.isEmpty)
    }

    func testBlockingStopStatesCannotReachCompletedOrEmitFileRemovalCommand() throws {
        let cases: [(name: String, input: RuntimeUninstallReadinessInput, blocker: String)] = [
            (
                "vm pid file missing",
                readiness(vmProcessState: .pidFileMissing, serviceState: .loaded),
                "vm-process-pid-file-missing"
            ),
            (
                "vm read failed",
                readiness(vmProcessState: .readFailed("pid read denied")),
                "vm-process-read-failed:reason=pid read denied"
            ),
            (
                "vm unknown",
                readiness(vmProcessState: .unknown("weird-vm-state")),
                "vm-process-state-unknown:value=weird-vm-state"
            ),
            (
                "service read failed",
                readiness(vmProcessState: .stopped, serviceState: .readFailed("launchctl failed")),
                "launchd-service-read-failed:label=\(RuntimeManagedService.watchdog.label)"
            ),
            (
                "service permission denied",
                readiness(vmProcessState: .stopped, serviceState: .permissionDenied("not root")),
                "launchd-service-permission-denied:label=\(RuntimeManagedService.watchdog.label)"
            ),
            (
                "service unknown",
                readiness(vmProcessState: .stopped, serviceState: .unknown("loaded-ish")),
                "launchd-service-state-unknown:label=\(RuntimeManagedService.watchdog.label)"
            ),
        ]

        for testCase in cases {
            let decision = try RuntimeUninstallTransitionPolicy.transition(
                from: .stopServicesRequested,
                event: .stoppedStateObserved(testCase.input)
            )

            XCTAssertEqual(decision.state, .serviceStopBlocked, testCase.name)
            XCTAssertNotEqual(decision.state, .completed, testCase.name)
            XCTAssertEqual(decision.persistedState, .serviceStopBlocked, testCase.name)
            XCTAssertEqual(decision.commands, [], testCase.name)
            XCTAssertTrue(
                decision.blockers.contains { $0.contains(testCase.blocker) },
                "\(testCase.name) blockers=\(decision.blockers)"
            )
        }
    }

    func testCleanupArtifactsMustBeExplicitlyAbsentBeforeReceiptForgetCommand() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .filesRemovalStarted,
            event: .cleanupArtifactsObserved([
                .inspectFailed(path: "/usr/local/bin/vitalserver-vm", reason: "permission denied"),
            ])
        )

        XCTAssertEqual(blocked.state, .filesRemovalBlocked)
        XCTAssertEqual(blocked.persistedState, .filesRemovalBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains {
            $0.contains("runtime-artifact-inspect-failed:path=/usr/local/bin/vitalserver-vm")
        })

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .filesRemovalStarted,
            event: .cleanupArtifactsObserved([
                .absent(path: "/usr/local/bin/vitalserver-vm"),
            ])
        )

        XCTAssertEqual(allowed.state, .cleanupVerified)
        XCTAssertEqual(allowed.commands, [.forgetPackageReceipts])
        XCTAssertTrue(allowed.blockers.isEmpty)
    }

    func testBlockingCleanupArtifactStatesCannotEmitReceiptForgetCommand() throws {
        let cases: [(name: String, state: RuntimeInstallArtifactState, blocker: String)] = [
            (
                "present artifact",
                .present(path: "/usr/local/bin/vitalserver-vm"),
                "runtime-artifact-present:path=/usr/local/bin/vitalserver-vm"
            ),
            (
                "inspect failed artifact",
                .inspectFailed(path: "/usr/local/bin/vitalserver-vm", reason: "permission denied"),
                "runtime-artifact-inspect-failed:path=/usr/local/bin/vitalserver-vm"
            ),
            (
                "unknown artifact",
                .unknown("mystery-artifact"),
                "runtime-artifact-state-unknown:value=mystery-artifact"
            ),
        ]

        for testCase in cases {
            let decision = try RuntimeUninstallTransitionPolicy.transition(
                from: .filesRemovalStarted,
                event: .cleanupArtifactsObserved([testCase.state])
            )

            XCTAssertEqual(decision.state, .filesRemovalBlocked, testCase.name)
            XCTAssertNotEqual(decision.state, .completed, testCase.name)
            XCTAssertEqual(decision.commands, [], testCase.name)
            XCTAssertTrue(
                decision.blockers.contains { $0.contains(testCase.blocker) },
                "\(testCase.name) blockers=\(decision.blockers)"
            )
        }
    }

    func testReceiptForgetSuccessMustBeFollowedByExplicitReceiptAbsenceBeforeCompletion() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .present(identifier: "ai.tirosh.vitalserver.helper"),
            ])
        )

        XCTAssertEqual(blocked.state, .receiptsForgetBlocked)
        XCTAssertEqual(blocked.persistedState, .receiptsForgetBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("package-receipt-present:identifier=ai.tirosh.vitalserver.helper"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .absent(identifier: "ai.tirosh.vitalserver.helper"),
            ])
        )

        XCTAssertEqual(allowed.state, .completed)
        XCTAssertEqual(allowed.persistedState, .completed)
        XCTAssertEqual(allowed.commands, [.complete])
        XCTAssertTrue(allowed.blockers.isEmpty)
    }

    func testBlockingReceiptStatesCannotComplete() throws {
        let cases: [(name: String, state: RuntimePackageReceiptState, blocker: String)] = [
            (
                "present receipt",
                .present(identifier: "ai.tirosh.vitalserver.helper"),
                "package-receipt-present:identifier=ai.tirosh.vitalserver.helper"
            ),
            (
                "receipt read failed",
                .readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "pkgutil denied"),
                "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper"
            ),
            (
                "receipt forget failed",
                .forgetFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "receipt locked"),
                "package-receipt-forget-failed:identifier=ai.tirosh.vitalserver.helper"
            ),
            (
                "receipt unknown",
                .unknown("mystery-receipt"),
                "package-receipt-state-unknown:value=mystery-receipt"
            ),
        ]

        for testCase in cases {
            let decision = try RuntimeUninstallTransitionPolicy.transition(
                from: .receiptsForgetStarted,
                event: .packageReceiptsObserved([testCase.state])
            )

            XCTAssertEqual(decision.state, .receiptsForgetBlocked, testCase.name)
            XCTAssertNotEqual(decision.state, .completed, testCase.name)
            XCTAssertEqual(decision.commands, [], testCase.name)
            XCTAssertTrue(
                decision.blockers.contains { $0.contains(testCase.blocker) },
                "\(testCase.name) blockers=\(decision.blockers)"
            )
        }
    }

    func testStartEventsPersistWithoutReemittingAlreadyApprovedCommands() throws {
        let fileRemovalStarted = try RuntimeUninstallTransitionPolicy.transition(
            from: .stoppedVerified,
            event: .filesRemovalStarted
        )

        XCTAssertEqual(fileRemovalStarted.state, .filesRemovalStarted)
        XCTAssertEqual(fileRemovalStarted.persistedState, .filesRemovalStarted)
        XCTAssertEqual(fileRemovalStarted.commands, [])

        let receiptsForgetStarted = try RuntimeUninstallTransitionPolicy.transition(
            from: .cleanupVerified,
            event: .receiptsForgetStarted
        )

        XCTAssertEqual(receiptsForgetStarted.state, .receiptsForgetStarted)
        XCTAssertEqual(receiptsForgetStarted.persistedState, .receiptsForgetStarted)
        XCTAssertEqual(receiptsForgetStarted.commands, [])
    }

    func testInvalidTransitionIsRejected() {
        XCTAssertThrowsError(
            try RuntimeUninstallTransitionPolicy.transition(
                from: .notStarted,
                event: .cleanupArtifactsObserved([])
            )
        ) { error in
            XCTAssertTrue(error is RuntimeUninstallTransitionError)
        }
    }

    private func readiness(
        vmProcessState: RuntimeVMProcessState,
        serviceState: RuntimeServiceState = .notLoaded
    ) -> RuntimeUninstallReadinessInput {
        RuntimeUninstallReadinessInput(
            serviceStates: Dictionary(uniqueKeysWithValues: RuntimeManagedService.stopOrder.map {
                ($0, serviceState)
            }),
            vmProcessState: vmProcessState,
            packageReceiptStates: []
        )
    }
}
