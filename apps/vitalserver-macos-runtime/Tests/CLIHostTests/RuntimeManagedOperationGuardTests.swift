import Foundation
import Bootstrap
import Application
import Contracts
import Domain
@testable import CLIHost
import XCTest
import Errors

final class RuntimeManagedOperationGuardTests: XCTestCase {
    func testOperationLeaseBlocksWatchdogRecovery() {
        var messages: [String] = []
        let guardPolicy = managedOperationGuard(
            operationLease: .loaded(operationLease(
                operationId: "apply-1",
                operation: .applyBundle,
                expiresAt: nil
            )),
            now: "2026-05-22T00:05:00Z",
            log: { messages.append($0) }
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .applyBundle)
        XCTAssertEqual(messages, [
            "watchdog operation lease guard active without expiresAt operation=apply-bundle operationId=apply-1",
        ])
    }

    func testOperationLeaseReadFailureBlocksWatchdogRecovery() {
        var messages: [String] = []
        let guardPolicy = managedOperationGuard(
            operationLease: .failed("permission denied"),
            now: "2026-05-22T00:05:00Z",
            log: { messages.append($0) }
        )

        XCTAssertEqual(guardPolicy.activeOperation(), .unknown("operation-lease-read-failed"))
        XCTAssertEqual(messages, [
            "watchdog operation lease guard blocked on lease read failure error=permission denied",
        ])
    }

    func testExpiredOperationLeaseDoesNotBlockRecovery() {
        var messages: [String] = []
        let guardPolicy = managedOperationGuard(
            operationLease: .loaded(operationLease(
                operationId: "apply-1",
                operation: .applyBundle,
                expiresAt: "2026-05-22T00:04:00Z"
            )),
            now: "2026-05-22T00:05:00Z",
            log: { messages.append($0) }
        )

        XCTAssertNil(guardPolicy.activeOperation())
        XCTAssertEqual(messages, [
            "watchdog operation lease guard expired operation=apply-bundle operationId=apply-1 expiredSeconds=60",
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
            let guardPolicy = managedOperationGuard(
                operationLease: .loaded(operationLease(
                    operationId: "managed-\(operation.rawValue)",
                    operation: operation,
                    expiresAt: nil
                )),
                now: "2026-05-22T00:05:00Z"
            )

            XCTAssertEqual(guardPolicy.activeOperation(), operation)
        }
    }

    private func managedOperationGuard(
        operationLease: RuntimeOperationLeaseLoadResult = .missing,
        now: String,
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition(
            operations: GuardManagedRuntimeOperationOperations(
                loadOperationLease: { operationLease },
                now: { ISO8601DateFormatter().date(from: now)! },
                log: log
            )
        )
    }

    private func operationLease(
        operationId: String,
        operation: RuntimeOperation,
        expiresAt: String?
    ) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationId,
            operation: operation,
            ownerPID: 123,
            startedAt: "2026-05-22T00:00:00Z",
            heartbeatAt: "2026-05-22T00:00:00Z",
            expiresAt: expiresAt,
            message: nil
        )
    }
}
