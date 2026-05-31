import Core
import Contracts
import XCTest

final class DatastoreRepairEvaluatorTests: XCTestCase {
    func testMissingResultWaits() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(nil),
            .wait(message: "waiting for datastore repair guest worker")
        )
    }

    func testPendingAndRunningWait() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .pending, message: "queued")),
            .wait(message: "queued")
        )
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .running, message: "repairing aof")),
            .wait(message: "repairing aof")
        )
    }

    func testCompletedSucceeds() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .completed, message: "done")),
            .completed(message: "done")
        )
    }

    func testFailedSkippedAndUnknownFail() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .failed, message: "compose failed")),
            .failed(message: "compose failed")
        )
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .skipped, message: "request missing")),
            .failed(message: "request missing")
        )
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(result(status: .unknown("paused"), message: nil)),
            .failed(message: "unknown datastore repair status: paused")
        )
    }

    func testMismatchedRequestIdFails() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(
                result(status: .completed, requestId: "old", message: "old done"),
                expectedRequestId: "new"
            ),
            .failed(message: "datastore repair result does not match the current request")
        )
    }

    func testV2ResultMissingRequestIdFailsWhenExpectedRequestIdExists() {
        XCTAssertEqual(
            DatastoreRepairEvaluator.evaluate(
                result(schemaVersion: 2, status: .completed, requestId: nil, message: "done"),
                expectedRequestId: "new"
            ),
            .failed(message: "datastore repair result is missing requestId")
        )
    }

    private func result(
        schemaVersion: Int? = nil,
        status: DatastoreRepairStatus,
        requestId: String? = nil,
        message: String?
    ) -> DatastoreRepairResultDocument {
        DatastoreRepairResultDocument(
            schemaVersion: schemaVersion,
            requestId: requestId,
            operation: .repairDatastore,
            status: status,
            message: message,
            updatedAt: "2026-05-21T12:33:57Z"
        )
    }
}
