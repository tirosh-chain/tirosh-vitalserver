import Foundation
import RuntimeCore
@testable import RuntimeOrchestrator
import XCTest

final class RuntimeManagedOperationGuardTests: XCTestCase {
    func testBlocksWatchdogRecoveryDuringFreshApplyBundleOperation() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = status(
            level: .updating,
            operation: .applyBundle,
            updatedAt: "2026-05-22T00:00:00Z"
        )
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:05:00Z"
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .applyBundle)
    }

    func testDoesNotBlockWatchdogRecoveryAfterGracePeriod() {
        var messages: [String] = []
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = status(
            level: .recovering,
            operation: .rollback,
            updatedAt: "2026-05-22T00:00:00Z"
        )
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:31:00Z",
            log: { messages.append($0) }
        )

        XCTAssertNil(guardPolicy.activeOperation())
        XCTAssertEqual(messages, [
            "watchdog active operation guard expired operation=rollback ageSeconds=1860",
        ])
    }

    func testIgnoresNonManagedOperations() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = status(
            level: .recovering,
            operation: .watchdog,
            updatedAt: "2026-05-22T00:00:00Z"
        )
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:01:00Z"
        )

        XCTAssertNil(guardPolicy.activeOperation())
    }

    private func managedOperationGuard(
        repository: RuntimeStatusRepositorySpy,
        now: String,
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: RuntimeStatusReporter(
                repository: repository,
                productRoot: URL(fileURLWithPath: "/product"),
                runtimeHome: URL(fileURLWithPath: "/product/vm")
            ),
            now: { ISO8601DateFormatter().date(from: now)! },
            graceSeconds: 1_800,
            log: log
        )
    }

    private func status(
        level: RuntimeStatusLevel,
        operation: RuntimeOperation,
        updatedAt: String
    ) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            product: "TiroshVitalServer",
            status: level,
            operation: operation,
            message: "status",
            updatedAt: updatedAt,
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            vmService: "loaded",
            proxyService: "loaded",
            watchdogService: "loaded",
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            rootfsBase: "present",
            vmDisk: "present",
            failureReasons: [],
            latestBackup: nil
        )
    }
}

private final class RuntimeStatusRepositorySpy: RuntimeStatusRepository {
    var loaded: RuntimeStatusDocument?

    func load() -> RuntimeStatusDocument? {
        loaded
    }

    func save(_ document: RuntimeStatusDocument) throws {}
}
