import Application
import Contracts
import Domain
import Foundation
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeHostSettingsRepositoryTests: XCTestCase {
    func testDesiredMaterializedBootAndAppliedRevisionsRequireExplicitProof() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-host-settings-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "settings-db" },
            timestamp: { "2026-07-14T08:00:00Z" }
        ).initialize()
        let repository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeHostSettingsActivationUseCase(),
            eventID: { UUID().uuidString }
        )

        let imported = try repository.importMaterializedHostSettings(
            payload("v1"),
            importedAt: "2026-07-14T08:00:00Z"
        )
        XCTAssertEqual(imported.revision, 1)
        XCTAssertEqual(imported.materializedRevision, 1)
        XCTAssertNil(imported.appliedPayload)
        XCTAssertTrue(imported.requiresVMRestart)

        let desired = try repository.saveDesiredHostSettings(
            payload("v2"),
            expectedRevision: 1,
            desiredAt: "2026-07-14T08:01:00Z"
        )
        XCTAssertEqual(desired.revision, 2)
        XCTAssertNil(desired.appliedPayload)
        XCTAssertNil(desired.materializedRevision)
        XCTAssertThrowsError(try repository.recordHostSettingsBoot(
            revision: 2,
            runID: "run-2",
            startedAt: "2026-07-14T08:02:00Z"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeHostSettingsActivationError,
                .notMaterialized(revision: 2)
            )
        }

        _ = try repository.markHostSettingsMaterialized(
            revision: 2,
            materializedAt: "2026-07-14T08:01:30Z"
        )
        let lifecycle = SQLiteRuntimeVMLifecycleStateRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        _ = try lifecycle.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
            document: RuntimeVMLifecycleDocument(
                state: .starting,
                operation: .configure,
                operationID: "operation-2",
                bootID: "run-2",
                startedAt: "2026-07-14T08:02:00Z",
                updatedAt: "2026-07-14T08:02:00Z"
            ),
            expectedRevision: nil
        ))
        let booted = try repository.recordHostSettingsBoot(
            revision: 2,
            runID: "run-2",
            startedAt: "2026-07-14T08:02:00Z"
        )
        XCTAssertEqual(booted.bootRevision, 2)
        XCTAssertEqual(booted.bootRunID, "run-2")

        _ = try lifecycle.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
            document: RuntimeVMLifecycleDocument(
                state: .bootstrapping,
                operation: .configure,
                operationID: "operation-2",
                bootID: "run-2",
                startedAt: "2026-07-14T08:02:00Z",
                updatedAt: "2026-07-14T08:02:10Z"
            ),
            expectedRevision: 1
        ))
        let applied = try repository.markHostSettingsApplied(
            revision: 2,
            runID: "run-2",
            appliedAt: "2026-07-14T08:03:00Z"
        )
        XCTAssertEqual(applied.appliedRevision, 2)
        XCTAssertEqual(applied.appliedRunID, "run-2")
        XCTAssertEqual(applied.appliedPayload, payload("v2"))
        XCTAssertFalse(applied.requiresVMRestart)

        let nextDesired = try repository.saveDesiredHostSettings(
            payload("v3"),
            expectedRevision: 2,
            desiredAt: "2026-07-14T08:04:00Z"
        )
        XCTAssertEqual(nextDesired.payload, payload("v3"))
        XCTAssertEqual(nextDesired.appliedRevision, 2)
        XCTAssertEqual(nextDesired.appliedPayload, payload("v2"))
        XCTAssertTrue(nextDesired.requiresVMRestart)
    }

    func testStaleDesiredWriteDoesNotAdvanceRevision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-host-settings-stale-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        let repository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        _ = try repository.importMaterializedHostSettings(payload("v1"), importedAt: "t1")

        XCTAssertThrowsError(try repository.saveDesiredHostSettings(
            payload("v2"),
            expectedRevision: 2,
            desiredAt: "t2"
        )) { error in
            XCTAssertEqual(
                error as? RuntimeHostSettingsActivationError,
                .staleRevision(expected: 2, actual: 1)
            )
        }
        guard case .loaded(let record) = repository.loadHostSettings() else {
            return XCTFail("expected loaded settings")
        }
        XCTAssertEqual(record.revision, 1)
    }

    func testInvalidJSONPayloadIsRejectedInsteadOfPersistedAsSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-host-settings-invalid-json-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        let repository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        let invalidData = Data("not-json".utf8)
        let invalidPayload = RuntimeHostSettingsPayload(
            vmConfigJSON: invalidData,
            guestRuntimeConfigJSON: invalidData,
            guestRuntimeSettingsJSON: invalidData
        )

        XCTAssertThrowsError(try repository.importMaterializedHostSettings(
            invalidPayload,
            importedAt: "t1"
        )) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeHostSettingsRepositoryError,
                .invalidStoredField(field: "vm_config_json", value: "invalid-json")
            )
        }
        XCTAssertEqual(repository.loadHostSettings(), .missing)
    }

    func testCorruptStoredJSONIsReportedAsReadFailureInsteadOfMissingOrDefaultSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-host-settings-corrupt-json-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        let repository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        _ = try repository.importMaterializedHostSettings(payload("v1"), importedAt: "t1")
        let connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: 5_000
        )
        try connection.withWritableDatabase { db in
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: "UPDATE host_runtime_settings SET vm_config_json = 'not-json' WHERE singleton_id = 1"
            )
        }

        guard case .failed(let reason) = repository.loadHostSettings() else {
            return XCTFail("expected explicit settings read failure")
        }
        XCTAssertTrue(reason.contains("vm_config_json"))
        XCTAssertTrue(reason.contains("invalid-json"))
    }

    private func payload(_ value: String) -> RuntimeHostSettingsPayload {
        let data = Data("{\"value\":\"\(value)\"}".utf8)
        return RuntimeHostSettingsPayload(
            vmConfigJSON: data,
            guestRuntimeConfigJSON: data,
            guestRuntimeSettingsJSON: data
        )
    }
}
