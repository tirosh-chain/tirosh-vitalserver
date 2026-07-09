import Application
import Contracts
import Errors
@testable import MacControlPanelHost
import OutboundAdapters
import RuntimeControl
import XCTest

@MainActor
final class RuntimeControlOperationLeaseControllerTests: XCTestCase {
    func testAcquireLoadHeartbeatAndReleaseOperationLease() async throws {
        let controller = RuntimeControlOperationLeaseController()
        let document = operationLease(operationId: "lease-1", operation: .applyBundle)

        let acquire = try await controller.acquireOperationLease(document)

        XCTAssertEqual(acquire.operationId, "lease-1")
        XCTAssertEqual(acquire.state, .acquired)
        XCTAssertEqual(controller.loadOperationLease(), .loaded(document))

        let heartbeat = try await controller.heartbeatOperationLease(
            operationId: "lease-1",
            heartbeatAt: "2026-07-09T01:05:00Z",
            expiresAt: "2026-07-09T02:05:00Z"
        )

        XCTAssertEqual(heartbeat.operationId, "lease-1")
        XCTAssertEqual(heartbeat.state, .heartbeatRecorded)
        guard case .loaded(let updated) = controller.loadOperationLease() else {
            return XCTFail("Expected updated operation lease")
        }
        XCTAssertEqual(updated.startedAt, document.startedAt)
        XCTAssertEqual(updated.heartbeatAt, "2026-07-09T01:05:00Z")
        XCTAssertEqual(updated.expiresAt, "2026-07-09T02:05:00Z")

        let release = try await controller.releaseOperationLease(operationId: "lease-1")

        XCTAssertEqual(release.operationId, "lease-1")
        XCTAssertEqual(release.state, .released)
        XCTAssertEqual(controller.loadOperationLease(), .missing)
    }

    func testAcquireFailsWhenOperationAlreadyExists() async throws {
        let controller = RuntimeControlOperationLeaseController()
        _ = try await controller.acquireOperationLease(operationLease(operationId: "lease-1", operation: .applyBundle))

        do {
            _ = try await controller.acquireOperationLease(operationLease(operationId: "lease-2", operation: .rollback))
            XCTFail("Expected existing operation error")
        } catch {
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .existingOperation(operationId: "lease-1", operation: "apply-bundle")
            )
        }
    }

    func testHeartbeatAndReleasePreserveOperationIDMismatch() async throws {
        let controller = RuntimeControlOperationLeaseController()
        let document = operationLease(operationId: "lease-1", operation: .applyBundle)
        _ = try await controller.acquireOperationLease(document)

        do {
            _ = try await controller.heartbeatOperationLease(
                operationId: "lease-2",
                heartbeatAt: "2026-07-09T01:05:00Z",
                expiresAt: nil
            )
            XCTFail("Expected heartbeat mismatch")
        } catch {
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }

        do {
            _ = try await controller.releaseOperationLease(operationId: "lease-2")
            XCTFail("Expected release mismatch")
        } catch {
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }

        XCTAssertEqual(controller.loadOperationLease(), .loaded(document))
    }

    private func operationLease(
        operationId: String,
        operation: RuntimeOperation
    ) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationId,
            operation: operation,
            ownerPID: 123,
            startedAt: "2026-07-09T01:00:00Z",
            heartbeatAt: "2026-07-09T01:00:00Z",
            expiresAt: nil,
            message: nil
        )
    }
}
