import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class DurableUpdateBootstrapHandoffLauncherTests: XCTestCase {
    func testPersistsJobBeforeStartingSupervisorAndUsesTerminalEvidence() throws {
        var events: [String] = []
        let invocation = makeInvocation()
        let launcher = DurableUpdateBootstrapHandoffLauncher(
            operations: DurableUpdateBootstrapHandoffLaunchOperations(
                fileState: { _ in .executable },
                submit: { jobId, submitted, invocationURL, updaterURL in
                    events.append("submit")
                    XCTAssertEqual(jobId, "job-42")
                    XCTAssertEqual(submitted, invocation)
                    XCTAssertEqual(
                        invocationURL.path,
                        "/updates/42/handoff/invocation.json"
                    )
                    XCTAssertEqual(
                        updaterURL.path,
                        "/updates/42/updater/next-updater"
                    )
                    return self.job(state: .queued, completion: nil)
                },
                startSupervisor: {
                    events.append("start")
                },
                waitForTerminal: { jobId in
                    events.append("wait:\(jobId)")
                    return self.job(
                        state: .succeeded,
                        completion: UpdateHandoffJobCompletion(
                            outcome: .succeeded,
                            exitCode: 0,
                            reason: nil,
                            finishedAt: "2026-07-29T00:00:01Z"
                        )
                    )
                }
            )
        )

        let result = try launcher.launch(
            jobId: "job-42",
            invocation: invocation,
            invocationURL: URL(
                fileURLWithPath: "/updates/42/handoff/invocation.json"
            ),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/42")
        )

        XCTAssertEqual(events, ["submit", "start", "wait:job-42"])
        XCTAssertEqual(result.exitCode, 0)
    }

    func testServiceStartDoesNotBecomeSuccessWithoutTerminalCompletion() {
        let launcher = DurableUpdateBootstrapHandoffLauncher(
            operations: DurableUpdateBootstrapHandoffLaunchOperations(
                fileState: { _ in .executable },
                submit: { _, _, _, _ in
                    self.job(state: .queued, completion: nil)
                },
                startSupervisor: {},
                waitForTerminal: { _ in
                    self.job(state: .running, completion: nil)
                }
            )
        )

        XCTAssertThrowsError(try launcher.launch(
            jobId: "job-42",
            invocation: makeInvocation(),
            invocationURL: URL(
                fileURLWithPath: "/updates/42/handoff/invocation.json"
            ),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/42")
        )) { error in
            XCTAssertEqual(
                error as? DurableUpdateBootstrapHandoffLaunchError,
                .terminalCompletionMissing(
                    jobId: "job-42",
                    state: .running
                )
            )
        }
    }

    func testRejectsSucceededJobWithoutExplicitZeroExitCode() {
        let launcher = DurableUpdateBootstrapHandoffLauncher(
            operations: DurableUpdateBootstrapHandoffLaunchOperations(
                fileState: { _ in .executable },
                submit: { _, _, _, _ in
                    self.job(state: .queued, completion: nil)
                },
                startSupervisor: {},
                waitForTerminal: { _ in
                    self.job(
                        state: .succeeded,
                        completion: UpdateHandoffJobCompletion(
                            outcome: .succeeded,
                            exitCode: nil,
                            reason: nil,
                            finishedAt: "2026-07-29T00:00:01Z"
                        )
                    )
                }
            )
        )

        XCTAssertThrowsError(try launcher.launch(
            jobId: "job-42",
            invocation: makeInvocation(),
            invocationURL: URL(
                fileURLWithPath: "/updates/42/handoff/invocation.json"
            ),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/42")
        )) { error in
            XCTAssertEqual(
                error as? DurableUpdateBootstrapHandoffLaunchError,
                .succeededWithoutZeroExitCode(
                    jobId: "job-42",
                    exitCode: nil
                )
            )
        }
    }

    private func makeInvocation() -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: "vitalserver.update-bootstrap-handoff/v1",
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            expectedJournalRevision: 3,
            updaterRelativePath: "updater/next-updater",
            specificationRelativePath: "spec/update.json",
            completionReceiptRelativePath: "handoff/completion-receipt.json"
        )
    }

    private func job(
        state: UpdateHandoffJobState,
        completion: UpdateHandoffJobCompletion?
    ) -> UpdateHandoffJobDocument {
        UpdateHandoffJobDocument(
            jobId: "job-42",
            revision: state == .queued ? 1 : 4,
            updateId: "update-42",
            operationId: "operation-42",
            invocationPath: "/updates/42/handoff/invocation.json",
            updaterPath: "/updates/42/updater/next-updater",
            launchId: state == .queued ? nil : "launch-42",
            state: state,
            child: nil,
            completion: completion,
            createdAt: "2026-07-29T00:00:00Z",
            updatedAt: "2026-07-29T00:00:01Z"
        )
    }
}
