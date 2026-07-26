import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeWatchdogDiagnosticProjectionCompositionTests: XCTestCase {
    func testWatchdogProjectsSQLiteOutboxBeforeAndAfterHealthEvaluation() throws {
        let harness = try Harness()

        try harness.composition().run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.paths.hostRuntimeStateEvents.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.paths.hostRuntimeStateSnapshot.path))
        XCTAssertTrue(harness.logs.contains { $0.contains("stage=before-watchdog events=1") })
        XCTAssertTrue(harness.logs.contains { $0.contains("stage=after-watchdog events=0") })
        XCTAssertFalse(harness.statuses.isEmpty)
    }

    func testDiagnosticFileFailureIsReportedWithoutChangingWatchdogHealthResult() throws {
        let harness = try Harness()
        try FileManager.default.createDirectory(
            at: harness.paths.hostRuntimeStateEvents,
            withIntermediateDirectories: true
        )

        try harness.composition().run()

        XCTAssertTrue(harness.logs.contains {
            $0.contains("Host diagnostics projection failed stage=before-watchdog")
                && $0.contains("Host diagnostic JSONL path state is unexpected")
        })
        XCTAssertTrue(harness.logs.contains {
            $0.contains("Host diagnostics projection failed stage=after-watchdog")
        })
        XCTAssertFalse(harness.statuses.isEmpty)
        XCTAssertEqual(harness.statuses.last?.0, .healthy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.paths.hostRuntimeStateSnapshot.path))
    }

    private final class Harness {
        let root: URL
        let paths: InstalledRuntimePaths
        var logs: [String] = []
        var statuses: [(RuntimeStatusLevel, RuntimeOperation, String)] = []

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("watchdog-diagnostic-projection-tests-\(UUID().uuidString)")
            paths = InstalledRuntimePaths(productRoot: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            _ = try SQLiteHostRuntimeStateDatabase(
                url: paths.runtimeStateDatabase,
                databaseID: { "watchdog-db" },
                timestamp: { "2026-07-14T11:00:00Z" }
            ).initialize()
            let data = Data("{\"value\":1}".utf8)
            _ = try SQLiteRuntimeHostSettingsRepository(
                databaseURL: paths.runtimeStateDatabase,
                transitionDecider: RuntimeHostSettingsActivationUseCase(),
                eventID: { "watchdog-settings-event" }
            ).importMaterializedHostSettings(
                RuntimeHostSettingsPayload(
                    vmConfigJSON: data,
                    guestRuntimeConfigJSON: data,
                    guestRuntimeSettingsJSON: data
                ),
                importedAt: "2026-07-14T11:00:00Z"
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func composition() -> RuntimeWatchdogRunnerComposition {
            RuntimeWatchdogRunnerComposition(
                context: RuntimeWatchdogRunnerCompositionContext(installedPaths: paths),
                operations: RuntimeWatchdogRunnerCompositionOperations(
                    fileStore: SystemRuntimeFileStore(),
                    now: { Date(timeIntervalSince1970: 1_784_030_400) },
                    activeManagedOperation: { nil },
                    healthSnapshot: { Self.healthySnapshot() },
                    httpStatusCode: { _ in "200" },
                    proxyLivenessURL: { _ in "http://127.0.0.1/health" },
                    automaticRecoveryEnabled: { false },
                    restartVMRuntime: { XCTFail("healthy watchdog must not restart VM") },
                    restartService: { _ in XCTFail("healthy watchdog must not restart services") },
                    createLogsDirectory: { .completed },
                    rotateRuntimeLogs: { .completed },
                    collectGuestLogs: { .completed },
                    writeRuntimeStatus: { [weak self] level, operation, message in
                        self?.statuses.append((level, operation, message))
                    },
                    recordObservedStatus: { _, _, _, _ in },
                    recordObservedEvent: { _, _, _, _, _ in },
                    recordLifecycleEvent: { _, _, _ in },
                    recoveryWaitSeconds: 0,
                    sleep: { _ in },
                    log: { [weak self] in self?.logs.append($0) },
                    printLine: { _ in }
                )
            )
        }

        private static func healthySnapshot() -> RuntimeHealthSnapshot {
            RuntimeHealthSnapshot(
                vmExecutable: .executable,
                proxyExecutable: .executable,
                rootfsBase: .present,
                vmDisk: .present,
                vmService: .loaded,
                proxyService: .loaded,
                watchdogService: .loaded,
                vmState: .running,
                vmIP: "192.168.64.2",
                proxyPort: 80,
                hostProxyHTTP: "200",
                guestHTTP: "200",
                redisUIHTTP: "200",
                swaggerUIHTTP: "200",
                failureReasons: []
            )
        }
    }
}
