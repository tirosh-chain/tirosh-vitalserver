import Foundation
import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeLifecycleProgressEventTests: XCTestCase {
    func testWriteRuntimeProgressRecordsEventWhenStatusDocumentIsMissing() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lifecycle-progress-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: productRoot)
        }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            runtimeStatusRepository: MissingRuntimeStatusRepository()
        )

        XCTAssertThrowsError(try lifecycle.writeRuntimeProgress(
            .updating,
            operation: .applyBundle,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started: stop-runtime-services"
        ))

        let eventRead = JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents).allResult()

        XCTAssertTrue(eventRead.issues.isEmpty)
        XCTAssertEqual(eventRead.events.count, 1)
        XCTAssertEqual(eventRead.events.first?.eventType, .progressUpdated)
        XCTAssertEqual(eventRead.events.first?.status, .updating)
        XCTAssertEqual(eventRead.events.first?.operation, .applyBundle)
        XCTAssertEqual(eventRead.events.first?.progress?.step, .stopRuntimeServices)
        XCTAssertEqual(eventRead.events.first?.progress?.stepStatus, .started)
    }
}

private struct MissingRuntimeStatusRepository: RuntimeStatusRepository {
    func loadResult() -> RuntimeStatusDocumentLoadResult {
        .missing
    }

    func save(_: RuntimeStatusDocument) throws {}
}
