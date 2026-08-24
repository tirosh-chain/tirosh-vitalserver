import Application
import Contracts
import Domain
import XCTest

final class ProveUpdateBootstrapLifecycleUseCaseTests: XCTestCase {
    func testRequiresExplicitJournalReadSuccess() {
        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().requireJournal(
                updateId: "update-42",
                journalRead: .failed(reason: "database unavailable")
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .journalReadFailed(
                    id: "update-42",
                    reason: "database unavailable"
                )
            )
        }
    }

    func testAcceptsCorrelatedSuccessfulTerminalDocuments() throws {
        let journal = terminalJournal(
            state: .succeeded,
            outcome: .succeeded
        )
        let report = report(
            journal: journal,
            state: .succeeded,
            rollback: .notRequired
        )

        let proven = try ProveUpdateBootstrapLifecycleUseCase().execute(
            expectation: .succeeded,
            journal: journal,
            report: report
        )

        XCTAssertEqual(proven.id, journal.id)
    }

    func testAcceptsExplicitFailedAndRolledBackTerminalDocuments() throws {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = report(
            journal: journal,
            state: .failed,
            rollback: .succeeded
        )

        XCTAssertNoThrow(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        )
    }

    func testWaitsForDelayedTerminalJournalWithoutGuessingCompletion() throws {
        let running = recoveryJournal(state: .running)
        let succeeded = terminalJournal(
            state: .succeeded,
            outcome: .succeeded
        )
        var reads = [running, running, succeeded]
        var elapsed: UInt64 = 0

        let journal = try ProveUpdateBootstrapLifecycleUseCase()
            .awaitTerminalJournal(
                updateId: succeeded.id,
                timeoutMilliseconds: 1_000,
                pollIntervalMilliseconds: 100,
                elapsedMilliseconds: { elapsed },
                wait: { elapsed += $0 },
                readJournal: { .loaded(reads.removeFirst()) }
            )

        XCTAssertEqual(journal.state, .succeeded)
        XCTAssertEqual(elapsed, 200)
        XCTAssertTrue(reads.isEmpty)
    }

    func testReportsLastOwnedStateWhenTerminalWaitTimesOut() {
        let running = recoveryJournal(state: .running)
        var elapsed: UInt64 = 0

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase()
                .awaitTerminalJournal(
                    updateId: running.id,
                    timeoutMilliseconds: 200,
                    pollIntervalMilliseconds: 100,
                    elapsedMilliseconds: { elapsed },
                    wait: { elapsed += $0 },
                    readJournal: { .loaded(running) }
                )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .terminalJournalWaitTimedOut(
                    id: running.id,
                    timeoutMilliseconds: 200,
                    lastState: .running
                )
            )
        }
    }

    func testRejectsRollbackProofWithoutHostFailureAndReverseReceipts() {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            updateSpecificationSHA256:
                journal.envelope.specification.sha256,
            state: .failed,
            startedAt: "2026-07-29T00:59:00Z",
            finishedAt: "2026-07-29T01:00:00Z",
            applyReceipts: [
                receipt(
                    journal: journal,
                    layer: .container,
                    operation: .apply,
                    state: .succeeded
                ),
                receipt(
                    journal: journal,
                    layer: .guestRuntime,
                    operation: .apply,
                    state: .failed
                ),
            ],
            rollbackReceipts: [
                receipt(
                    journal: journal,
                    layer: .container,
                    operation: .rollback,
                    state: .succeeded
                ),
            ],
            rollback: rollbackEvidence(.succeeded),
            failure: failureIssue()
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostFailureRollbackEvidenceInvalid(
                    applyLayers: [.container, .guestRuntime],
                    rollbackLayers: [.container]
                )
            )
        }
    }

    func testProveGuestControlMapsLoopbackToDistinctProofError() {
        let invocation = handoffInvocation(
            guestControlBaseURL: "http://127.0.0.1:18330/"
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveGuestControl(
                invocation: invocation,
                guestAddressRead: .loaded(
                    address: "127.0.0.1",
                    source: .platformAgent
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .guestControlBaseURLHostLoopback("http://127.0.0.1:18330/")
            )
        }
    }

    func testProveGuestControlMapsReadFailedWithoutComparingHosts() {
        let invocation = handoffInvocation()

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveGuestControl(
                invocation: invocation,
                guestAddressRead: .readFailed("permission denied")
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .guestAddressReadFailed("permission denied")
            )
        }
    }

    func testProveGuestControlAcceptsMatchingLoadedGuestAddress() throws {
        try ProveUpdateBootstrapLifecycleUseCase().proveGuestControl(
            invocation: handoffInvocation(),
            guestAddressRead: .loaded(
                address: "192.168.64.3",
                source: .platformAgent
            )
        )
    }

    func testProveGuestControlMapsOmittedPortToPortMismatch() {
        let invocation = handoffInvocation(
            guestControlBaseURL: "http://192.168.64.3"
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveGuestControl(
                invocation: invocation,
                guestAddressRead: .loaded(
                    address: "192.168.64.3",
                    source: .platformAgent
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .guestControlPortMismatch(
                    actual: nil,
                    expected: RuntimeGuestControlEndpointContract.port
                )
            )
        }
    }

    func testProveHostPlatformMapsMissingOperationWithoutGuessingPhase() {
        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveHostPlatform(
                expectation: .succeeded,
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "b", count: 64),
                operationRead: .missing,
                installationRead: .loaded(try! initialHostManifest())
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostPlatformOperationMissing(
                    id: "update-42.host-platform.apply"
                )
            )
        }
    }

    func testProveHostPlatformMapsOperationReadFailure() {
        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveHostPlatform(
                expectation: .succeeded,
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "b", count: 64),
                operationRead: .failed(reason: "database unavailable"),
                installationRead: .loaded(try! initialHostManifest())
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostPlatformOperationReadFailed(
                    id: "update-42.host-platform.apply",
                    reason: "database unavailable"
                )
            )
        }
    }

    func testProveHostPlatformMapsMissingInstallation() throws {
        let settlement = try completedHostSettlement()

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().proveHostPlatform(
                expectation: .succeeded,
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "b", count: 64),
                operationRead: .loaded(settlement.operation),
                installationRead: .missing
            )
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostPlatformInstallationMissing
            )
        }
    }

    func testProveHostPlatformAcceptsCompletedApply() throws {
        let settlement = try completedHostSettlement()

        let proven = try ProveUpdateBootstrapLifecycleUseCase()
            .proveHostPlatform(
                expectation: .succeeded,
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "b", count: 64),
                operationRead: .loaded(settlement.operation),
                installationRead: .loaded(settlement.manifest)
            )

        XCTAssertEqual(proven.phase, .completed)
        XCTAssertEqual(proven.id, "update-42.host-platform.apply")
    }

    func testProveHostPlatformAcceptsCompensatedApplyForRollbackExpectation() throws {
        let compensated = try compensatedHostOperation()

        let proven = try ProveUpdateBootstrapLifecycleUseCase()
            .proveHostPlatform(
                expectation: .failedRolledBack,
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "b", count: 64),
                operationRead: .loaded(compensated),
                installationRead: .loaded(try initialHostManifest())
            )

        XCTAssertEqual(proven.phase, .compensated)
    }

    func testRequireHostPlatformLayerRejectsSpecificationWithoutHostLayer() {
        let specification = ProductUpdateSpecification(
            schemaVersion: "vitalserver.product-update-specification/v1",
            id: "specification-42",
            bootstrapEnvelopeId: "envelope-42",
            layerPlan: []
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase()
                .requireHostPlatformLayer(specification: specification)
        ) { error in
            XCTAssertEqual(
                error as? ProveUpdateBootstrapLifecycleError,
                .hostPlatformLayerMissing
            )
        }
    }

    func testDoesNotTreatFailedWithoutRollbackAsRollbackProof() {
        let journal = terminalJournal(
            state: .failed,
            outcome: .failed
        )
        let report = report(
            journal: journal,
            state: .failed,
            rollback: .failed
        )

        XCTAssertThrowsError(
            try ProveUpdateBootstrapLifecycleUseCase().execute(
                expectation: .failedRolledBack,
                journal: journal,
                report: report
            )
        )
    }

    private func terminalJournal(
        state: UpdateBootstrapJournalState,
        outcome: UpdateBootstrapCompletionOutcome
    ) -> UpdateBootstrapJournal {
        let base = recoveryJournal(state: .running)
        return UpdateBootstrapJournal(
            schemaVersion: base.schemaVersion,
            id: base.id,
            journalRevision: base.journalRevision + 1,
            operationId: base.operationId,
            targetInstallationId: base.targetInstallationId,
            expectedInstallationRevision:
                base.expectedInstallationRevision,
            requestId: base.requestId,
            envelope: base.envelope,
            bootstrapSignedSHA256: base.bootstrapSignedSHA256,
            state: state,
            stagedUpdaterRelativePath: base.stagedUpdaterRelativePath,
            stagedSpecificationRelativePath:
                base.stagedSpecificationRelativePath,
            completion: UpdateBootstrapCompletionReceipt(
                schemaVersion: "v1",
                updateId: base.id,
                requestId: base.requestId,
                bootstrapEnvelopeId: base.envelope.id,
                updateSpecificationSHA256:
                    base.envelope.specification.sha256,
                expectedJournalRevision: base.journalRevision,
                outcome: outcome,
                reportRelativePath: "handoff/report.json",
                reportSHA256: String(repeating: "c", count: 64),
                failureReason: outcome == .failed
                    ? "host effect failed"
                    : nil,
                finishedAt: "2026-07-29T01:00:00Z"
            ),
            failureReason: outcome == .failed
                ? "host effect failed"
                : nil,
            createdAt: base.createdAt,
            updatedAt: "2026-07-29T01:00:00Z"
        )
    }

    private func report(
        journal: UpdateBootstrapJournal,
        state: ProductUpdateExecutionState,
        rollback: ProductUpdateRollbackState
    ) -> ProductUpdateExecutionReport {
        let failedApplyReceipts: [ProductUpdateLayerEffectReceipt] = [
            receipt(
                journal: journal,
                layer: .container,
                operation: .apply,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .guestRuntime,
                operation: .apply,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .hostPlatform,
                operation: .apply,
                state: .failed
            ),
        ]
        let successfulRollbackReceipts: [ProductUpdateLayerEffectReceipt] = [
            receipt(
                journal: journal,
                layer: .guestRuntime,
                operation: .rollback,
                state: .succeeded
            ),
            receipt(
                journal: journal,
                layer: .container,
                operation: .rollback,
                state: .succeeded
            ),
        ]
        return ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            requestId: journal.requestId,
            bootstrapEnvelopeId: journal.envelope.id,
            updateSpecificationSHA256:
                journal.envelope.specification.sha256,
            state: state,
            startedAt: "2026-07-29T00:59:00Z",
            finishedAt: "2026-07-29T01:00:00Z",
            applyReceipts: state == .failed ? failedApplyReceipts : [],
            rollbackReceipts: rollback == .succeeded
                ? successfulRollbackReceipts
                : [],
            rollback: rollbackEvidence(rollback),
            failure: state == .failed ? failureIssue() : nil
        )
    }

    private func receipt(
        journal: UpdateBootstrapJournal,
        layer: UpdateLayer,
        operation: ProductUpdateLayerEffectOperation,
        state: ProductUpdateLayerEffectState
    ) -> ProductUpdateLayerEffectReceipt {
        ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: journal.id,
            layer: layer,
            effectExecutorId: "\(layer.rawValue)-effect-executor",
            operation: operation,
            artifactSHA256: String(repeating: "d", count: 64),
            state: state,
            observedAt: "2026-07-29T01:00:00Z",
            evidence: ProductUpdateEvidenceReference(
                kind: "layer-effect",
                id: "\(layer.rawValue):\(operation.rawValue)"
            ),
            issue: state == .failed ? failureIssue() : nil
        )
    }

    private func rollbackEvidence(
        _ state: ProductUpdateRollbackState
    ) -> ProductUpdateRollbackEvidence {
        ProductUpdateRollbackEvidence(
            state: state,
            observedAt: "2026-07-29T01:00:00Z",
            evidence: state == .succeeded
                ? ProductUpdateEvidenceReference(
                    kind: "product-update-rollback",
                    id: "update-42:rollback"
                )
                : nil,
            issue: state == .failed
                ? ProductUpdateIssue(
                    code: "rollback-failed",
                    message: "rollback failed",
                    retryable: false,
                    dependency: "effect-executor"
                )
                : nil
        )
    }

    private func failureIssue() -> ProductUpdateIssue {
        ProductUpdateIssue(
            code: "host-effect-failed",
            message: "host effect failed",
            retryable: false,
            dependency: "host-platform-effect-executor"
        )
    }

    private func handoffInvocation(
        guestControlBaseURL: String = "http://192.168.64.3:18330"
    ) -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: UpdateBootstrapHandoffPolicy.schemaVersion,
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            updateSpecificationSHA256: String(repeating: "c", count: 64),
            guestControlBaseURL: guestControlBaseURL,
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            payloadArtifacts: [],
            expectedJournalRevision: 3,
            updaterRelativePath: "payload/bin/vitalserver-update",
            specificationRelativePath: "payload/update-specification.json",
            completionReceiptRelativePath: "handoff/completion-receipt.json"
        )
    }

    private func applyTransition() -> HostPlatformLayerTransition {
        HostPlatformLayerTransition(
            installationId: "installation-1",
            expectedInstallationRevision: 1,
            targetReleaseId: "host-0.2.2",
            targetReleaseVersion: "0.2.2",
            targetSlotRelativePath: "releases/host-0.2.2"
        )
    }

    private func completedHostSettlement() throws -> (
        operation: HostPlatformInstallationOperation,
        manifest: HostPlatformInstallationManifest
    ) {
        let published = try HostPlatformInstallationPolicy
            .recordPublishInterfaces(
                operation: try HostPlatformInstallationPolicy
                    .recordQuiescePrevious(
                        operation: try stagedHostOperation(),
                        observations: [],
                        updatedAt: "2026-07-29T01:00:02Z"
                    ),
                updatedAt: "2026-07-29T01:00:03Z"
            )
        let loaded = try HostPlatformInstallationPolicy
            .recordLoadTargetServices(
                operation: try HostPlatformInstallationPolicy
                    .recordActivateTarget(
                        operation: published,
                        resolvedTarget: "/install/releases/host-0.2.2/release",
                        updatedAt: "2026-07-29T01:00:04Z"
                    ),
                observations: [],
                updatedAt: "2026-07-29T01:00:05Z"
            )
        return try HostPlatformInstallationPolicy.makeCompletedSettlement(
            operation: loaded,
            settledAt: "2026-07-29T01:00:06Z"
        )
    }

    private func compensatedHostOperation() throws -> HostPlatformInstallationOperation {
        let published = try HostPlatformInstallationPolicy
            .recordPublishInterfaces(
                operation: try HostPlatformInstallationPolicy
                    .recordQuiescePrevious(
                        operation: try stagedHostOperation(),
                        observations: [],
                        updatedAt: "2026-07-29T01:00:02Z"
                    ),
                updatedAt: "2026-07-29T01:00:03Z"
            )
        let compensating = try HostPlatformInstallationPolicy.recordCompensating(
            operation: published,
            reason: "target service load failed",
            updatedAt: "2026-07-29T01:00:04Z"
        )
        return try HostPlatformInstallationPolicy.recordCompensated(
            operation: compensating,
            updatedAt: "2026-07-29T01:00:05Z"
        )
    }

    private func stagedHostOperation() throws -> HostPlatformInstallationOperation {
        try HostPlatformInstallationPolicy.recordStagedCandidate(
            operation: try requestedHostOperation(),
            candidate: HostPlatformStagedCandidate(
                release: hostTargetRelease(),
                stagingReceiptId: "update-42.candidate",
                stagedAt: "2026-07-29T01:00:01Z"
            ),
            updatedAt: "2026-07-29T01:00:01Z"
        )
    }

    private func requestedHostOperation() throws -> HostPlatformInstallationOperation {
        try HostPlatformInstallationPolicy.makeRequestedOperation(
            command: HostPlatformInstallationCommand(
                operationId: "update-42.host-platform.apply",
                kind: .apply,
                installationId: "installation-1",
                expectedInstallationRevision: 1,
                targetRelease: hostTargetRelease(),
                sourceArtifactPath: "/incoming/host-platform.pkg",
                sourceArtifactSizeBytes: 1024,
                sourceArtifactMediaType:
                    HostPlatformReleaseArchiveContract.mediaType,
                stagingAttemptId: "update-42.apply",
                requestedAt: "2026-07-29T01:00:00Z"
            ),
            activeManifest: try initialHostManifest()
        )
    }

    private func initialHostManifest() throws -> HostPlatformInstallationManifest {
        try HostPlatformInstallationPolicy.makeInitialManifest(
            installationId: "installation-1",
            activeRelease: HostPlatformRelease(
                id: "host-0.2.1",
                version: "0.2.1",
                sha256: String(repeating: "a", count: 64),
                slotRelativePath: "releases/host-0.2.1"
            ),
            operationId: "fresh-install.host-0.2.1",
            activatedAt: "2026-07-29T00:00:00Z"
        )
    }

    private func hostTargetRelease() -> HostPlatformRelease {
        HostPlatformRelease(
            id: "host-0.2.2",
            version: "0.2.2",
            sha256: String(repeating: "b", count: 64),
            slotRelativePath: "releases/host-0.2.2"
        )
    }
}
