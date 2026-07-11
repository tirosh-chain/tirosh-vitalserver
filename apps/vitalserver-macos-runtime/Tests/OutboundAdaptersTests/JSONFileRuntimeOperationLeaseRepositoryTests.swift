import Application
import Contracts
import Errors
import Foundation
@testable import OutboundAdapters
import XCTest

final class JSONFileRuntimeOperationLeaseRepositoryTests: XCTestCase {
    func testAcquireLoadHeartbeatAndReleasePersistAcrossReaders() throws {
        let fixture = makeRepository()
        let document = lease(operationId: "lease-1")

        try fixture.repository.acquire(document)
        XCTAssertEqual(
            JSONFileRuntimeOperationLeaseRepository(url: fixture.url).loadOperationLease(),
            .loaded(document)
        )

        try fixture.repository.heartbeat(
            operationId: "lease-1",
            heartbeatAt: "2026-07-11T01:05:00Z",
            expiresAt: "2026-07-11T02:05:00Z"
        )
        guard case .loaded(let updated) = fixture.repository.loadOperationLease() else {
            return XCTFail("Expected loaded lease")
        }
        XCTAssertEqual(updated.startedAt, document.startedAt)
        XCTAssertEqual(updated.heartbeatAt, "2026-07-11T01:05:00Z")

        try fixture.repository.release(operationId: "lease-1")
        XCTAssertEqual(fixture.repository.loadOperationLease(), .missing)
    }

    func testAcquireRejectsExistingOperation() throws {
        let fixture = makeRepository()
        try fixture.repository.acquire(lease(operationId: "lease-1"))

        XCTAssertThrowsError(try fixture.repository.acquire(lease(operationId: "lease-2"))) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .existingOperation(operationId: "lease-1", operation: "apply-bundle")
            )
        }
    }

    func testInvalidDocumentStaysFailed() throws {
        let fixture = makeRepository()
        try FileManager.default.createDirectory(
            at: fixture.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.url)

        guard case .failed(let reason) = fixture.repository.loadOperationLease() else {
            return XCTFail("Expected failed lease read")
        }
        XCTAssertTrue(reason.contains("read failed"))
    }

    func testMismatchPreservesLease() throws {
        let fixture = makeRepository()
        let document = lease(operationId: "lease-1")
        try fixture.repository.acquire(document)

        XCTAssertThrowsError(try fixture.repository.release(operationId: "lease-2")) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }
        XCTAssertEqual(fixture.repository.loadOperationLease(), .loaded(document))
    }

    private func makeRepository() -> (repository: JSONFileRuntimeOperationLeaseRepository, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONFileRuntimeOperationLeaseRepositoryTests-\(UUID().uuidString)")
            .appendingPathComponent("runtime-operation-lease.json")
        return (JSONFileRuntimeOperationLeaseRepository(url: url), url)
    }

    private func lease(operationId: String) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationId,
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-11T01:00:00Z",
            heartbeatAt: "2026-07-11T01:00:00Z",
            expiresAt: nil,
            message: nil
        )
    }
}
