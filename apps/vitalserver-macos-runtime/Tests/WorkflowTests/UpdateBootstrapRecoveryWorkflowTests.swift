import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest

final class UpdateBootstrapRecoveryWorkflowTests: XCTestCase {
    func testResumePersistsRunningBeforeLaunchAndSettlesReceipt() throws {
        let pending = recoveryPendingJournal()
        let advance = AdvanceUpdateBootstrapJournalUseCase()
        let settle = SettleUpdateBootstrapHandoffUseCase()
        var events: [String] = []
        var saved: [(UpdateBootstrapJournalState, Int)] = []

        let output = try ResumeUpdateBootstrapHandoffWorkflow().run(
            input: ResumeUpdateBootstrapHandoffWorkflowInput(
                pendingJournal: pending,
                stagedRoot: URL(fileURLWithPath: "/updates/update-42")
            ),
            operations: ResumeUpdateBootstrapHandoffWorkflowOperations(
                saveJournal: { journal, expectedRevision in
                    saved.append((journal.state, expectedRevision))
                    events.append("save-\(journal.state.rawValue)")
                },
                handoffStarted: advance.handoffStarted,
                makeInvocation:
                    MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                writeInvocation: { _, _ in
                    events.append("write-invocation")
                    return WrittenUpdateBootstrapHandoffInvocation(
                        url: URL(
                            fileURLWithPath:
                                "/updates/update-42/handoff/invocation.json"
                        )
                    )
                },
                launch: { _, _, _ in
                    events.append("launch")
                    return RuntimeProcessResult(
                        exitCode: 7,
                        stdout: "",
                        stderr: ""
                    )
                },
                readReceipt: { _ in
                    events.append("read-receipt")
                    return .loaded(
                        recoveryReceipt(
                            revision: 3,
                            outcome: .failed
                        )
                    )
                },
                settle: settle.execute,
                readReport: { path, _ in
                    .loaded(
                        path: path,
                        sha256: String(repeating: "c", count: 64)
                    )
                },
                verifyReport:
                    VerifyUpdateBootstrapCompletionReportUseCase().verify,
                makeInstalledRelease: { _ in
                    XCTFail("failed receipt must not create release")
                    throw RecoveryWorkflowTestError.unexpected
                },
                settleSucceeded: { _, _, _, _ in
                    XCTFail("failed receipt must not settle release")
                },
                fail: advance.failed,
                now: { "2026-07-27T01:00:00Z" },
                describeFailure: { String(describing: $0) }
            )
        )

        XCTAssertEqual(output.journal.state, .failed)
        XCTAssertEqual(output.updaterExitCode, 7)
        XCTAssertEqual(saved.map(\.0), [.running, .failed])
        XCTAssertEqual(saved.map(\.1), [2, 3])
        XCTAssertEqual(events, [
            "save-running",
            "write-invocation",
            "launch",
            "read-receipt",
            "save-failed",
        ])
    }

    func testSettleRunningConsumesReceiptWithoutLaunchingUpdater() throws {
        let running = recoveryRunningJournal()
        let settle = SettleUpdateBootstrapHandoffUseCase()
        var saved: [(UpdateBootstrapJournalState, Int)] = []

        let output = try SettleRunningUpdateBootstrapWorkflow().run(
            input: SettleRunningUpdateBootstrapWorkflowInput(
                runningJournal: running,
                stagedRoot: URL(fileURLWithPath: "/updates/update-42")
            ),
            operations: SettleRunningUpdateBootstrapWorkflowOperations(
                makeInvocation:
                    MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                readReceipt: { url in
                    XCTAssertEqual(
                        url.path,
                        "/updates/update-42/handoff/completion-receipt.json"
                    )
                    return .loaded(
                        recoveryReceipt(
                            revision: 3,
                            outcome: .failed
                        )
                    )
                },
                settle: settle.execute,
                readReport: { path, _ in
                    .loaded(
                        path: path,
                        sha256: String(repeating: "c", count: 64)
                    )
                },
                verifyReport:
                    VerifyUpdateBootstrapCompletionReportUseCase().verify,
                saveJournal: { journal, expectedRevision in
                    saved.append((journal.state, expectedRevision))
                },
                makeInstalledRelease: { _ in
                    XCTFail("failed receipt must not create release")
                    throw RecoveryWorkflowTestError.unexpected
                },
                settleSucceeded: { _, _, _, _ in
                    XCTFail("failed receipt must not settle release")
                }
            )
        )

        XCTAssertEqual(output.state, .failed)
        XCTAssertEqual(saved.map(\.0), [.failed])
        XCTAssertEqual(saved.map(\.1), [3])
    }

    func testMissingReceiptLeavesRunningJournalUnchanged() {
        let running = recoveryRunningJournal()
        var saveCalled = false

        XCTAssertThrowsError(
            try SettleRunningUpdateBootstrapWorkflow().run(
                input: SettleRunningUpdateBootstrapWorkflowInput(
                    runningJournal: running,
                    stagedRoot: URL(fileURLWithPath: "/updates/update-42")
                ),
                operations: SettleRunningUpdateBootstrapWorkflowOperations(
                    makeInvocation:
                        MakeUpdateBootstrapHandoffInvocationUseCase().execute,
                    readReceipt: { _ in
                        .missing(
                            path:
                                "/updates/update-42/handoff/completion-receipt.json"
                        )
                    },
                    settle: SettleUpdateBootstrapHandoffUseCase().execute,
                    readReport: { path, _ in
                        .loaded(
                            path: path,
                            sha256: String(repeating: "c", count: 64)
                        )
                    },
                    verifyReport:
                        VerifyUpdateBootstrapCompletionReportUseCase()
                            .verify,
                    saveJournal: { _, _ in saveCalled = true },
                    makeInstalledRelease: { _ in
                        throw RecoveryWorkflowTestError.unexpected
                    },
                    settleSucceeded: { _, _, _, _ in
                        saveCalled = true
                    }
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SettleUpdateBootstrapHandoffError,
                .receiptMissing(
                    path:
                        "/updates/update-42/handoff/completion-receipt.json"
                )
            )
        }
        XCTAssertFalse(saveCalled)
    }
}

private enum RecoveryWorkflowTestError: Error {
    case unexpected
}

private func recoveryPendingJournal() -> UpdateBootstrapJournal {
    recoveryWorkflowJournal(state: .handoffPending, revision: 2)
}

private func recoveryRunningJournal() -> UpdateBootstrapJournal {
    recoveryWorkflowJournal(state: .running, revision: 3)
}

private func recoveryWorkflowJournal(
    state: UpdateBootstrapJournalState,
    revision: Int
) -> UpdateBootstrapJournal {
    UpdateBootstrapJournal(
        schemaVersion: "v2",
        id: "update-42",
        journalRevision: revision,
        operationId: "operation-42",
        targetInstallationId: "installation-1",
        expectedInstallationRevision: 1,
        requestId: "request-42",
        envelope: UpdateBootstrapEnvelope(
            schemaVersion: "v1",
            id: "envelope-42",
            productId: "com.tirosh.vitalserver-helper",
            target: UpdateBootstrapTarget(
                platform: .macos,
                architecture: .arm64
            ),
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.2",
                runtimeVersion: "0.2.2"
            ),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            nextUpdaterArtifact: recoveryArtifact(
                id: "next-updater",
                path: "payload/bin/vitalserver-update"
            ),
            specification: recoveryArtifact(
                id: "update-specification",
                path: "payload/update-specification.json"
            ),
            signature: UpdateBootstrapSignature(
                algorithm: .ed25519,
                keyId: "release-key-1",
                signedSha256: String(repeating: "a", count: 64),
                value: "c2lnbmF0dXJl"
            ),
            issuedAt: "2026-07-27T00:00:00Z"
        ),
        bootstrapSignedSHA256: String(repeating: "a", count: 64),
        state: state,
        stagedUpdaterRelativePath: "payload/bin/vitalserver-update",
        stagedSpecificationRelativePath:
            "payload/update-specification.json",
        completion: nil,
        failureReason: nil,
        createdAt: "2026-07-27T00:00:00Z",
        updatedAt: "2026-07-27T00:01:00Z"
    )
}

private func recoveryArtifact(
    id: String,
    path: String
) -> UpdateBootstrapArtifact {
    UpdateBootstrapArtifact(
        id: id,
        relativePath: path,
        sha256: String(repeating: "b", count: 64),
        sizeBytes: 64,
        mediaType: "application/octet-stream"
    )
}

private func recoveryReceipt(
    revision: Int,
    outcome: UpdateBootstrapCompletionOutcome
) -> UpdateBootstrapCompletionReceipt {
    UpdateBootstrapCompletionReceipt(
        schemaVersion: "v1",
        updateId: "update-42",
        requestId: "request-42",
        bootstrapEnvelopeId: "envelope-42",
        updateSpecificationSHA256: String(repeating: "b", count: 64),
        expectedJournalRevision: revision,
        outcome: outcome,
        reportRelativePath: "handoff/report.json",
        reportSHA256: String(repeating: "c", count: 64),
        failureReason: outcome == .failed ? "updater failed" : nil,
        finishedAt: "2026-07-27T01:10:00Z"
    )
}
