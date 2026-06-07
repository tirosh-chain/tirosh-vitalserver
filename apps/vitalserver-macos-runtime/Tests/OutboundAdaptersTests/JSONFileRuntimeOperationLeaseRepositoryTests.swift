import Application
import Contracts
import Errors
import OutboundAdapters
import XCTest

final class JSONFileRuntimeOperationLeaseRepositoryTests: XCTestCase {
    func testAcquireLoadAndReleaseOperationLease() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        let document = operationLease(operationId: "lease-1", operation: .applyBundle)

        try repository.acquire(document)

        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected loaded operation lease")
        }
        XCTAssertEqual(loaded, document)

        try repository.release(operationId: "lease-1")
        XCTAssertEqual(repository.loadResult(), .missing)

        try? FileManager.default.removeItem(at: directory)
    }

    func testAcquireFailsWhenOperationLeaseAlreadyExists() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        XCTAssertThrowsError(try repository.acquire(operationLease(operationId: "lease-2", operation: .rollback))) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseRepositoryError,
                .existingOperation(operationId: "lease-1", operation: "apply-bundle")
            )
        }

        try? FileManager.default.removeItem(at: directory)
    }

    func testReleaseFailsWhenOperationIdDoesNotMatch() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)
        try repository.acquire(operationLease(operationId: "lease-1", operation: .applyBundle))

        XCTAssertThrowsError(try repository.release(operationId: "lease-2")) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseRepositoryError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }
        guard case .loaded(let loaded) = repository.loadResult() else {
            return XCTFail("Expected mismatched release to preserve lease")
        }
        XCTAssertEqual(loaded.operationId, "lease-1")

        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadResultReportsInvalidOperationLeaseDocument() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(RuntimeFileNames.runtimeOperationLease)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        let repository = JSONFileRuntimeOperationLeaseRepository(url: url)

        guard case .failed(let message) = repository.loadResult() else {
            return XCTFail("Expected failed operation lease load")
        }
        XCTAssertFalse(message.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    private func operationLease(
        operationId: String,
        operation: RuntimeOperation
    ) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationId,
            operation: operation,
            ownerPID: 123,
            startedAt: "2026-05-22T00:00:00Z",
            heartbeatAt: "2026-05-22T00:00:00Z",
            expiresAt: nil,
            message: nil
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
