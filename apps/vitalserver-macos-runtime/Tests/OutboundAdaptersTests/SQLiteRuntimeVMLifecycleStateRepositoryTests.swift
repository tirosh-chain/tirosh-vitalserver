import Application
import Contracts
import Domain
import Foundation
import SQLite3
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeVMLifecycleStateRepositoryTests: XCTestCase {
    func testReadOnlyMissingDatabaseDoesNotCreateIt() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("runtime-state.sqlite")
        let repository = SQLiteRuntimeVMLifecycleStateRepository(
            databaseURL: url,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )

        guard case .failed(let reason) = repository.loadVMLifecycleState() else {
            return XCTFail("expected explicit read failure for missing database")
        }
        XCTAssertTrue(reason.contains("open failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPersistsTransitionsAndOutboxInSameRevisionOrder() throws {
        let harness = try Harness()
        let starting = harness.document(state: .starting)

        let first = try harness.repository.saveVMLifecycleState(
            RuntimeVMLifecycleStateMutation(document: starting, expectedRevision: nil)
        )
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(harness.repository.loadVMLifecycleState(), .loaded(first))

        let bootstrapping = harness.document(
            state: .bootstrapping,
            updatedAt: "2026-07-14T07:00:01Z"
        )
        let second = try harness.repository.saveVMLifecycleState(
            RuntimeVMLifecycleStateMutation(document: bootstrapping, expectedRevision: 1)
        )
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(try harness.scalarInt("SELECT COUNT(*) FROM diagnostic_outbox"), 2)
        XCTAssertEqual(
            try harness.scalarInt("SELECT MAX(aggregate_revision) FROM diagnostic_outbox WHERE aggregate_type = 'vm-lifecycle'"),
            2
        )
    }

    func testStaleTransitionDoesNotWriteStateOrOutbox() throws {
        let harness = try Harness()
        _ = try harness.repository.saveVMLifecycleState(
            RuntimeVMLifecycleStateMutation(document: harness.document(state: .starting), expectedRevision: nil)
        )

        XCTAssertThrowsError(try harness.repository.saveVMLifecycleState(
            RuntimeVMLifecycleStateMutation(
                document: harness.document(state: .bootstrapping, updatedAt: "2026-07-14T07:00:01Z"),
                expectedRevision: 2
            )
        )) { error in
            XCTAssertEqual(
                error as? RuntimeVMLifecycleTransitionError,
                .staleRevision(expected: 2, actual: 1)
            )
        }
        XCTAssertEqual(try harness.scalarInt("SELECT revision FROM vm_lifecycle"), 1)
        XCTAssertEqual(try harness.scalarInt("SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }
}

private extension SQLiteRuntimeVMLifecycleStateRepositoryTests {
    final class Harness {
        let directory: URL
        let databaseURL: URL
        let repository: SQLiteRuntimeVMLifecycleStateRepository

        init() throws {
            directory = try temporaryDirectory()
            databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
            _ = try SQLiteHostRuntimeStateDatabase(
                url: databaseURL,
                databaseID: { "db-lifecycle" },
                timestamp: { "2026-07-14T07:00:00Z" }
            ).initialize()
            repository = SQLiteRuntimeVMLifecycleStateRepository(
                databaseURL: databaseURL,
                eventID: { UUID().uuidString },
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
        }

        func document(
            state: RuntimeVMLifecycleState,
            updatedAt: String = "2026-07-14T07:00:00Z"
        ) -> RuntimeVMLifecycleDocument {
            RuntimeVMLifecycleDocument(
                state: state,
                operation: .startServices,
                operationID: "operation-1",
                bootID: "boot-1",
                startedAt: "2026-07-14T07:00:00Z",
                updatedAt: updatedAt,
                deadlineAt: state == .starting || state == .bootstrapping
                    ? "2026-07-14T07:05:00Z"
                    : nil,
                terminalReason: state == .failed ? .launchFailed : nil,
                message: state.rawValue
            )
        }

        func scalarInt(_ sql: String) throws -> Int {
            var db: OpaquePointer?
            guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let db else {
                throw NSError(domain: "test", code: 1)
            }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw NSError(domain: "test", code: 2)
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw NSError(domain: "test", code: 3)
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-vm-lifecycle-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func temporaryDirectory() throws -> URL {
        try Self.temporaryDirectory()
    }
}
