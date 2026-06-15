import Contracts
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeStatusRefresherTests: XCTestCase {
    func testRefreshHealthStatusLoadsHealthSnapshotAndFormatsMessage() async {
        let healthStatus = RuntimeStatus(runtimeInstalled: true, statusMessage: "Runtime is healthy.")
        let snapshots = StubStatusSnapshotLoader(healthStatus: healthStatus)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshHealthStatus(settings: RuntimeSettings(), isBusy: false)

        XCTAssertEqual(snapshots.loadHealthStatusCount, 1)
        XCTAssertEqual(snapshots.loadStatusCount, 0)
        XCTAssertEqual(result.status, healthStatus)
        XCTAssertEqual(result.message, "Runtime is healthy.")
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testRefreshStatusSynchronizesFileBackedUpdatePresentationWhenIdle() async {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeState: .updating,
            operation: .applyBundle,
            progress: RuntimeProgressDocument(
                operation: .applyBundle,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "Applying bundle",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-05-30T00:00:00Z"
            )
        )
        let snapshots = StubStatusSnapshotLoader(status: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshStatus(settings: RuntimeSettings(), isBusy: false)

        XCTAssertEqual(result.status, status)
        XCTAssertEqual(result.message, "Applying bundle")
        XCTAssertEqual(result.operationDetail, "Applying bundle")
        XCTAssertEqual(result.selectedLogSource, .command)
    }

    func testRefreshStatusDoesNotOverridePresentationWhileBusy() async {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeState: .updating,
            operation: .applyBundle,
            statusMessage: "Status document message"
        )
        let snapshots = StubStatusSnapshotLoader(status: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshStatus(settings: RuntimeSettings(), isBusy: true)

        XCTAssertEqual(result.message, "Status document message")
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testHealthCheckStatusPrefixesCompletedMessageWithoutFileBackedOverride() async {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeState: .updating,
            operation: .applyBundle,
            statusMessage: "Still updating"
        )
        let snapshots = StubStatusSnapshotLoader(healthStatus: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.healthCheckStatus(
            settings: RuntimeSettings(),
            completedMessage: "Health check completed"
        )

        XCTAssertEqual(result.message, "Health check completed\n\nStill updating")
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testOperationDetailPrefersProgressMessage() async {
        let status = RuntimeStatus(
            progress: RuntimeProgressDocument(
                operation: .repairServices,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "Restarting services",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-05-30T00:00:00Z"
            )
        )
        let snapshots = StubStatusSnapshotLoader(status: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.operationDetail(
            settings: RuntimeSettings(),
            pendingDetail: "Waiting"
        )

        XCTAssertEqual(result.status, status)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.operationDetail, "Restarting services")
        XCTAssertNil(result.selectedLogSource)
    }
}

@MainActor
private final class StubStatusSnapshotLoader: RuntimeStatusSnapshotLoading {
    let status: RuntimeStatus
    let healthStatus: RuntimeStatus
    private(set) var loadStatusCount = 0
    private(set) var loadHealthStatusCount = 0

    init(
        status: RuntimeStatus = RuntimeStatus(),
        healthStatus: RuntimeStatus = RuntimeStatus()
    ) {
        self.status = status
        self.healthStatus = healthStatus
    }

    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        loadStatusCount += 1
        return status
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        loadHealthStatusCount += 1
        return healthStatus
    }
}
