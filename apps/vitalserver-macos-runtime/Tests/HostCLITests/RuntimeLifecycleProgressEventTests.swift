import Foundation
import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeLifecycleProgressEventTests: XCTestCase {
    func testWriteRuntimeProgressRecordsEventWhenStatusDocumentIsMissing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lifecycle-progress-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: home)
        }
        let installedPaths = InstalledRuntimePaths(runtimeHome: home)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: home,
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

        let events = JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents).all()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, .progressUpdated)
        XCTAssertEqual(events.first?.status, .updating)
        XCTAssertEqual(events.first?.operation, .applyBundle)
        XCTAssertEqual(events.first?.progress?.step, .stopRuntimeServices)
        XCTAssertEqual(events.first?.progress?.stepStatus, .started)
    }
}

private struct MissingRuntimeStatusRepository: RuntimeStatusRepository {
    func load() -> RuntimeStatusDocument? {
        nil
    }

    func save(_: RuntimeStatusDocument) throws {}
}
