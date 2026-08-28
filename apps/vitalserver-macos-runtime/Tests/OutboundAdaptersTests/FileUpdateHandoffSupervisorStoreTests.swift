import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class FileUpdateHandoffSupervisorStoreTests: XCTestCase {
    func testPersistsAndLoadsJobAcrossStoreInstances() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = makeStore(root)
        let job = queued()
        try first.save(job, expectedRevision: nil)

        let restarted = makeStore(root)

        XCTAssertEqual(try restarted.load(jobId: job.jobId), job)
        XCTAssertEqual(try restarted.loadAll(), [job])
    }

    func testRejectsStaleRevisionInsteadOfOverwritingOwnedState() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        let job = queued()
        try store.save(job, expectedRevision: nil)
        let launching = try UpdateHandoffJobStateMachine.transition(
            job,
            event: .launchClaimed(
                launchId: "launch-1",
                observedAt: "2026-07-29T00:01:00Z"
            )
        )

        XCTAssertThrowsError(try store.save(
            launching,
            expectedRevision: 99
        )) { error in
            XCTAssertEqual(
                error as? FileUpdateHandoffSupervisorStoreError,
                .revisionConflict(
                    jobId: "job-1",
                    expected: 99,
                    actual: 1
                )
            )
        }
        XCTAssertEqual(try store.load(jobId: "job-1").state, .queued)
    }

    private func makeStore(_ root: URL) -> FileUpdateHandoffSupervisorStore {
        FileUpdateHandoffSupervisorStore(
            root: root,
            validate: ValidateUpdateHandoffJobUseCase().validate
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func queued() -> UpdateHandoffJobDocument {
        UpdateHandoffJobStateMachine.enqueue(
            jobId: "job-1",
            updateId: "update-1",
            operationId: "operation-1",
            invocationPath: "/updates/update-1/invocation.json",
            updaterPath: "/updates/update-1/updater",
            observedAt: "2026-07-29T00:00:00Z"
        )
    }
}
