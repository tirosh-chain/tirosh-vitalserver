import Application
import Contracts
import Foundation
import SQLite3
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeEndpointStateRepositoryTests: XCTestCase {
    func testEndpointRequiresMatchingBootAndLifecycleRevision() throws {
        let harness = try Harness()
        let lifecycle = try harness.writeBootstrappingLifecycle()

        XCTAssertThrowsError(try harness.endpointRepository.saveRuntimeEndpointState(
            RuntimeEndpointStateMutation(
                runID: "stale-boot",
                lifecycleRevision: lifecycle.revision,
                address: "192.168.64.2",
                source: .platformAgent,
                observedAt: "2026-07-14T07:00:02Z",
                expectedRevision: nil
            )
        )) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeEndpointStateRepositoryError,
                .lifecycleMismatch(expectedRunID: "boot-1", actualRunID: "stale-boot")
            )
        }
        XCTAssertEqual(try harness.scalarInt("SELECT COUNT(*) FROM runtime_endpoint"), 0)
    }

    func testEndpointBecomesStaleWhenItsBootStops() throws {
        let harness = try Harness()
        let lifecycle = try harness.writeBootstrappingLifecycle()
        let endpoint = try harness.endpointRepository.saveRuntimeEndpointState(
            RuntimeEndpointStateMutation(
                runID: "boot-1",
                lifecycleRevision: lifecycle.revision,
                address: "192.168.64.2",
                source: .platformAgent,
                observedAt: "2026-07-14T07:00:02Z",
                expectedRevision: nil
            )
        )
        XCTAssertEqual(harness.endpointRepository.loadRuntimeEndpointState(), .loaded(endpoint))

        let stopping = harness.document(state: .stopping, updatedAt: "2026-07-14T07:00:03Z")
        _ = try harness.lifecycleRepository.saveVMLifecycleState(
            RuntimeVMLifecycleStateMutation(document: stopping, expectedRevision: lifecycle.revision)
        )

        guard case .stale(let stale, let reason) = harness.endpointRepository.loadRuntimeEndpointState() else {
            return XCTFail("expected stale endpoint")
        }
        XCTAssertEqual(stale, endpoint)
        XCTAssertTrue(reason.contains("stopping"))
    }
}

private extension SQLiteRuntimeEndpointStateRepositoryTests {
    final class Harness {
        let databaseURL: URL
        let lifecycleRepository: SQLiteRuntimeVMLifecycleStateRepository
        let endpointRepository: SQLiteRuntimeEndpointStateRepository

        init() throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("sqlite-runtime-endpoint-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
            _ = try SQLiteHostRuntimeStateDatabase(
                url: databaseURL,
                databaseID: { "db-endpoint" },
                timestamp: { "2026-07-14T07:00:00Z" }
            ).initialize()
            lifecycleRepository = SQLiteRuntimeVMLifecycleStateRepository(
                databaseURL: databaseURL,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
            endpointRepository = SQLiteRuntimeEndpointStateRepository(databaseURL: databaseURL)
        }

        func writeBootstrappingLifecycle() throws -> RuntimeVMLifecycleStateRecord {
            _ = try lifecycleRepository.saveVMLifecycleState(
                RuntimeVMLifecycleStateMutation(document: document(state: .starting), expectedRevision: nil)
            )
            return try lifecycleRepository.saveVMLifecycleState(
                RuntimeVMLifecycleStateMutation(
                    document: document(state: .bootstrapping, updatedAt: "2026-07-14T07:00:01Z"),
                    expectedRevision: 1
                )
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
                message: state.rawValue
            )
        }

        func scalarInt(_ sql: String) throws -> Int {
            var db: OpaquePointer?
            guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let db else { throw NSError(domain: "test", code: 1) }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw NSError(domain: "test", code: 2)
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw NSError(domain: "test", code: 3) }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }
}
