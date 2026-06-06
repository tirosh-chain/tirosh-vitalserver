import Foundation
import Core
import Contracts
@testable import HostCLI
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

    func testBlocksWatchdogRecoveryDuringInstall() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = status(
            level: .installing,
            operation: .install,
            updatedAt: "2026-05-22T00:00:00Z"
        )
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:05:00Z"
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .install)
    }

    func testDoesNotBlockWatchdogRecoveryAfterInstallProvisionCompletes() {
        let repository = RuntimeStatusRepositorySpy()
        repository.loaded = status(
            level: .degraded,
            operation: .install,
            updatedAt: "2026-05-22T00:00:00Z"
        )
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:05:00Z"
        )

        XCTAssertNil(guardPolicy.activeOperation())
    }

    func testBlocksWatchdogRecoveryDuringFreshGuestBootstrap() {
        let repository = RuntimeStatusRepositorySpy()
        let guardPolicy = managedOperationGuard(
            repository: repository,
            activeGuestBootstrap: RuntimeGuestBootstrapOperation(
                operation: .unknown("bootstrap"),
                updatedAt: ISO8601DateFormatter().date(from: "2026-05-22T00:00:00Z")!
            ),
            now: "2026-05-22T00:05:00Z"
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .unknown("bootstrap"))
    }

    func testDoesNotBlockWatchdogRecoveryForStaleGuestBootstrap() {
        var messages: [String] = []
        let repository = RuntimeStatusRepositorySpy()
        let guardPolicy = managedOperationGuard(
            repository: repository,
            activeGuestBootstrap: RuntimeGuestBootstrapOperation(
                operation: .unknown("bootstrap"),
                updatedAt: ISO8601DateFormatter().date(from: "2026-05-22T00:00:00Z")!
            ),
            now: "2026-05-22T00:31:00Z",
            log: { messages.append($0) }
        )

        XCTAssertNil(guardPolicy.activeOperation())
        XCTAssertEqual(messages, [
            "watchdog guest bootstrap guard expired operation=bootstrap ageSeconds=1860",
        ])
    }

    func testBlocksWatchdogRecoveryDuringRunningGuestBootstrapWithoutUpdatedAt() {
        var messages: [String] = []
        let repository = RuntimeStatusRepositorySpy()
        let guardPolicy = managedOperationGuard(
            repository: repository,
            activeGuestBootstrap: RuntimeGuestBootstrapOperation(
                operation: .unknown("bootstrap"),
                updatedAt: nil
            ),
            now: "2026-05-22T00:31:00Z",
            log: { messages.append($0) }
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .unknown("bootstrap"))
        XCTAssertEqual(messages, [
            "watchdog guest bootstrap guard active without updatedAt operation=bootstrap",
        ])
    }

    func testBlocksWatchdogRecoveryDuringProtectedRuntimeOperations() {
        let protectedOperations: [RuntimeOperation] = [
            .redisBackup,
            .repairDatastore,
            .repairVMDisk,
            .startServices,
            .stopServices,
            .uninstall,
        ]

        for operation in protectedOperations {
            let repository = RuntimeStatusRepositorySpy()
            repository.loaded = status(
                level: .recovering,
                operation: operation,
                updatedAt: "2026-05-22T00:00:00Z"
            )
            let guardPolicy = managedOperationGuard(
                repository: repository,
                now: "2026-05-22T00:05:00Z"
            )

            XCTAssertEqual(guardPolicy.activeOperation(), operation)
        }
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

    func testLogsStatusReadFailureWithoutBlockingRecovery() {
        var messages: [String] = []
        let repository = RuntimeStatusRepositorySpy()
        repository.result = .failed("status unreadable")
        let guardPolicy = managedOperationGuard(
            repository: repository,
            now: "2026-05-22T00:01:00Z",
            log: { messages.append($0) }
        )

        XCTAssertNil(guardPolicy.activeOperation())
        XCTAssertEqual(messages, [
            "watchdog active operation guard ignored status read failure error=status unreadable",
        ])
    }


    private func managedOperationGuard(
        repository: RuntimeStatusRepositorySpy,
        activeGuestBootstrap: RuntimeGuestBootstrapOperation? = nil,
        now: String,
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: RuntimeStatusReporter(
                repository: repository,
                productIdentifier: Constants.Product.identifier,
                productRoot: URL(fileURLWithPath: "/product"),
                runtimeHome: URL(fileURLWithPath: "/product/vm")
            ),
            activeGuestBootstrap: { activeGuestBootstrap },
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
            product: "VitalServerHelper",
            status: level,
            operation: operation,
            message: "status",
            updatedAt: updatedAt,
            productRoot: "/product",
            runtimeHome: "/product/vm",
            runtimeVersion: "0.1.0",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [],
            latestBackup: nil
        )
    }
}

private final class RuntimeStatusRepositorySpy: RuntimeStatusRepository {
    var result: RuntimeStatusDocumentLoadResult = .missing

    var loaded: RuntimeStatusDocument? {
        get {
            guard case .loaded(let document) = result else {
                return nil
            }
            return document
        }
        set {
            result = newValue.map(RuntimeStatusDocumentLoadResult.loaded) ?? .missing
        }
    }

    func loadResult() -> RuntimeStatusDocumentLoadResult {
        result
    }

    func save(_ document: RuntimeStatusDocument) throws {}
}
