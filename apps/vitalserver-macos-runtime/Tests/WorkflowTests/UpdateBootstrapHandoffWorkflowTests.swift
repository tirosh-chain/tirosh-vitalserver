import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest

final class UpdateBootstrapHandoffWorkflowTests: XCTestCase {
    func testPersistsEveryTransitionBeforeAndAfterFixedHandoff() throws {
        let harness = HandoffWorkflowHarness()

        let output = try UpdateBootstrapHandoffWorkflow().run(
            input: harness.input,
            operations: harness.operations()
        )

        XCTAssertEqual(output.journal.state, .succeeded)
        XCTAssertEqual(output.updaterExitCode, 9)
        XCTAssertEqual(harness.saved, [
            SavedJournal(state: .admitted, revision: 1, expectedRevision: nil),
            SavedJournal(state: .handoffPending, revision: 2, expectedRevision: 1),
            SavedJournal(state: .running, revision: 3, expectedRevision: 2),
        ])
        XCTAssertEqual(harness.settledRelease?.journalRevision, 4)
        XCTAssertEqual(harness.settledExpectedRevision, 3)
        XCTAssertEqual(harness.events, [
            "stage",
            "write-invocation",
            "launch",
            "read-receipt:/updates/update-42/handoff/completion-receipt.json",
            "settle-installed-release",
        ])
    }

    func testLaunchFailurePersistsExplicitFailedJournal() {
        let harness = HandoffWorkflowHarness(launchError: TestWorkflowError.launch)

        XCTAssertThrowsError(try UpdateBootstrapHandoffWorkflow().run(
            input: harness.input,
            operations: harness.operations()
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffWorkflowError,
                .operationFailed(reason: "launch")
            )
        }
        XCTAssertEqual(harness.saved.last, SavedJournal(
            state: .failed,
            revision: 4,
            expectedRevision: 3
        ))
    }

    func testSettlementFailurePersistsFailureFromRunningState() {
        let harness = HandoffWorkflowHarness(
            settlementError: TestWorkflowError.settlement
        )

        XCTAssertThrowsError(try UpdateBootstrapHandoffWorkflow().run(
            input: harness.input,
            operations: harness.operations()
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffWorkflowError,
                .operationFailed(reason: "settlement")
            )
        }
        XCTAssertEqual(harness.saved.last, SavedJournal(
            state: .failed,
            revision: 4,
            expectedRevision: 3
        ))
        XCTAssertNil(harness.settledRelease)
    }

    func testFailurePersistencePreservesBothFailures() {
        let harness = HandoffWorkflowHarness(
            launchError: TestWorkflowError.launch,
            failPersistence: true
        )

        XCTAssertThrowsError(try UpdateBootstrapHandoffWorkflow().run(
            input: harness.input,
            operations: harness.operations()
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffWorkflowError,
                .operationAndFailurePersistenceFailed(
                    operationReason: "launch",
                    persistenceReason: "persistence"
                )
            )
        }
    }

    func testFailureTransitionRemainsDistinctFromPersistenceFailure() {
        let harness = HandoffWorkflowHarness(
            launchError: TestWorkflowError.launch,
            failTransitionError: TestWorkflowError.transition
        )

        XCTAssertThrowsError(try UpdateBootstrapHandoffWorkflow().run(
            input: harness.input,
            operations: harness.operations()
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffWorkflowError,
                .operationAndFailureTransitionFailed(
                    operationReason: "launch",
                    transitionReason: "transition"
                )
            )
        }
    }
}

private enum TestWorkflowError: Error {
    case launch
    case settlement
    case transition
    case persistence
}

private struct SavedJournal: Equatable {
    let state: UpdateBootstrapJournalState
    let revision: Int
    let expectedRevision: Int?
}

private final class HandoffWorkflowHarness {
    var saved: [SavedJournal] = []
    var events: [String] = []
    var settledRelease: InstalledUpdateRelease?
    var settledExpectedRevision: Int?

    private let launchError: Error?
    private let settlementError: Error?
    private let failPersistence: Bool
    private let failTransitionError: Error?

    init(
        launchError: Error? = nil,
        settlementError: Error? = nil,
        failPersistence: Bool = false,
        failTransitionError: Error? = nil
    ) {
        self.launchError = launchError
        self.settlementError = settlementError
        self.failPersistence = failPersistence
        self.failTransitionError = failTransitionError
    }

    var input: UpdateBootstrapHandoffWorkflowInput {
        UpdateBootstrapHandoffWorkflowInput(
            admittedJournal: admittedJournal(),
            verification: VerifiedUpdateBootstrapClosure(
                updateId: "envelope-42",
                canonicalPayloadSHA256: String(repeating: "a", count: 64),
                verifiedArtifactIds: ["next-updater", "update-specification"]
            ),
            staging: UpdateBootstrapStagingInput(
                updateId: "update-42",
                stagingAttemptId: "attempt-7",
                sourceBundle: URL(fileURLWithPath: "/source/bundle")
            )
        )
    }

    func operations() -> UpdateBootstrapHandoffWorkflowOperations {
        let advance = AdvanceUpdateBootstrapJournalUseCase()
        let makeInvocation = MakeUpdateBootstrapHandoffInvocationUseCase()
        let settle = SettleUpdateBootstrapHandoffUseCase()
        let makeRelease = MakeInstalledUpdateReleaseUseCase()
        return UpdateBootstrapHandoffWorkflowOperations(
            saveJournal: { [self] journal, expectedRevision in
                if failPersistence, journal.state == .failed {
                    throw TestWorkflowError.persistence
                }
                saved.append(SavedJournal(
                    state: journal.state,
                    revision: journal.journalRevision,
                    expectedRevision: expectedRevision
                ))
            },
            stage: { [self] _ in
                events.append("stage")
                return StagedUpdateBootstrapBundle(
                    root: URL(fileURLWithPath: "/updates/update-42")
                )
            },
            verifiedAndStaged: {
                try advance.verifiedAndStaged(
                    journal: $0,
                    verification: $1,
                    updaterRelativePath: $2,
                    specificationRelativePath: $3,
                    observedAt: $4
                )
            },
            handoffStarted: {
                try advance.handoffStarted(journal: $0, observedAt: $1)
            },
            makeInvocation: {
                try makeInvocation.execute(journal: $0)
            },
            writeInvocation: { [self] _, _ in
                events.append("write-invocation")
                return WrittenUpdateBootstrapHandoffInvocation(
                    url: URL(
                        fileURLWithPath:
                            "/updates/update-42/handoff/invocation.json"
                    )
                )
            },
            launch: { [self] _, _, _ in
                events.append("launch")
                if let launchError {
                    throw launchError
                }
                return RuntimeProcessResult(exitCode: 9, stdout: "", stderr: "")
            },
            readReceipt: { [self] url in
                events.append("read-receipt:\(url.path)")
                return .loaded(receipt(revision: 3))
            },
            settle: {
                try settle.execute(journal: $0, receiptRead: $1)
            },
            makeInstalledRelease: {
                try makeRelease.make(from: $0)
            },
            settleSucceeded: { [self] _, release, expectedRevision in
                events.append("settle-installed-release")
                if let settlementError {
                    throw settlementError
                }
                settledRelease = release
                settledExpectedRevision = expectedRevision
            },
            fail: { [self] in
                if let failTransitionError {
                    throw failTransitionError
                }
                return try advance.failed(
                    journal: $0,
                    reason: $1,
                    observedAt: $2
                )
            },
            now: { "2026-07-27T06:05:00Z" },
            describeFailure: { String(describing: $0) }
        )
    }

    private func admittedJournal() -> UpdateBootstrapJournal {
        UpdateBootstrapJournal(
            schemaVersion: "v1",
            id: "update-42",
            journalRevision: 1,
            operationId: "operation-42",
            requestId: "request-42",
            envelope: envelope(),
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            state: .admitted,
            stagedUpdaterRelativePath: nil,
            stagedSpecificationRelativePath: nil,
            completion: nil,
            failureReason: nil,
            createdAt: "2026-07-27T06:00:00Z",
            updatedAt: "2026-07-27T06:00:00Z"
        )
    }

    private func receipt(revision: Int) -> UpdateBootstrapCompletionReceipt {
        UpdateBootstrapCompletionReceipt(
            schemaVersion: "v1",
            updateId: "update-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: revision,
            outcome: .succeeded,
            reportRelativePath: "handoff/report.json",
            reportSHA256: String(repeating: "c", count: 64),
            failureReason: nil,
            finishedAt: "2026-07-27T06:10:00Z"
        )
    }

    private func envelope() -> UpdateBootstrapEnvelope {
        UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "envelope-42",
            productId: "com.tirosh.vitalserver-helper",
            target: UpdateBootstrapTarget(platform: .macos, architecture: .arm64),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: artifact(
                id: "next-updater",
                path: "updater/next-updater"
            ),
            specification: artifact(
                id: "update-specification",
                path: "spec/update.json"
            ),
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key-1",
                signedSha256: String(repeating: "a", count: 64),
                value: "c2lnbmF0dXJl"
            ),
            issuedAt: "2026-07-27T06:00:00Z"
        )
    }

    private func artifact(id: String, path: String) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: String(repeating: "b", count: 64),
            sizeBytes: 64,
            mediaType: "application/octet-stream"
        )
    }
}
