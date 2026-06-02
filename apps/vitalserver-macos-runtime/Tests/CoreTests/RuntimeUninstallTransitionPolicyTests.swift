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
            event: .stoppedStateObserved(readiness(vmProcessState: .pidFileMissing))
        )

        XCTAssertEqual(blocked.state, .serviceStopBlocked)
        XCTAssertEqual(blocked.persistedState, .serviceStopBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("vm-process-pid-file-missing"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .stopServicesRequested,
            event: .stoppedStateObserved(readiness(vmProcessState: .stopped))
        )

        XCTAssertEqual(allowed.state, .stoppedVerified)
        XCTAssertEqual(allowed.commands, [.removeFiles])
        XCTAssertTrue(allowed.blockers.isEmpty)
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

    func testReceiptForgetSuccessMustBeFollowedByExplicitReceiptAbsenceBeforeCompletion() throws {
        let blocked = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .present(identifier: "com.tirosh.vitalserver.vm"),
            ])
        )

        XCTAssertEqual(blocked.state, .receiptsForgetBlocked)
        XCTAssertEqual(blocked.persistedState, .receiptsForgetBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertTrue(blocked.blockers.contains("package-receipt-present:identifier=com.tirosh.vitalserver.vm"))

        let allowed = try RuntimeUninstallTransitionPolicy.transition(
            from: .receiptsForgetStarted,
            event: .packageReceiptsObserved([
                .absent(identifier: "com.tirosh.vitalserver.vm"),
            ])
        )

        XCTAssertEqual(allowed.state, .completed)
        XCTAssertEqual(allowed.persistedState, .completed)
        XCTAssertEqual(allowed.commands, [.complete])
        XCTAssertTrue(allowed.blockers.isEmpty)
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
