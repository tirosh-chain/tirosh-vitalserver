import Contracts
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeStatusRefresherTests: XCTestCase {
    func testRefreshHealthStatusLoadsHealthSnapshotAndFormatsMessage() async {
        let healthStatus = platformState(runtimeInstallationState: .executable)
        let snapshots = StubStatusSnapshotLoader(healthStatus: healthStatus)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshHealthStatus(settings: RuntimeSettings(), isBusy: false)

        XCTAssertEqual(snapshots.loadHealthStatusCount, 1)
        XCTAssertEqual(snapshots.loadStatusCount, 0)
        XCTAssertEqual(snapshots.loadOperationStateCount, 1)
        XCTAssertEqual(result.status, healthStatus)
        XCTAssertNil(result.operationState.activeOperation)
        XCTAssertNil(result.message)
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testRefreshStatusIncludesOperationStatePresentationWhenIdle() async {
        let status = platformState(
            runtimeInstallationState: .executable,
            runtimeState: .updating
        )
        let snapshots = StubStatusSnapshotLoader(
            status: status,
            operationState: PlatformOperationState(
                activeOperation: .applyBundle,
                install: .unavailable()
            )
        )
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshStatus(settings: RuntimeSettings(), isBusy: false)

        XCTAssertEqual(result.status, status)
        XCTAssertEqual(result.operationState.activeOperation, .applyBundle)
        XCTAssertEqual(result.message, "Apply Bundle in progress")
        XCTAssertEqual(result.operationDetail, "Apply Bundle in progress")
        XCTAssertEqual(result.selectedLogSource, .command)
    }

    func testRefreshStatusDoesNotUseLegacyStatusMessageWhileBusy() async {
        let status = platformState(
            runtimeInstallationState: .executable,
            runtimeState: .updating
        )
        let snapshots = StubStatusSnapshotLoader(status: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.refreshStatus(settings: RuntimeSettings(), isBusy: true)

        XCTAssertNil(result.message)
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testHealthCheckStatusPrefixesCompletedMessageWithoutOperationStateOverride() async {
        let status = platformState(
            runtimeInstallationState: .executable,
            runtimeState: .updating
        )
        let snapshots = StubStatusSnapshotLoader(healthStatus: status)
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.healthCheckStatus(
            settings: RuntimeSettings(),
            completedMessage: "Health check completed"
        )

        XCTAssertEqual(result.message, "Health check completed")
        XCTAssertNil(result.operationDetail)
        XCTAssertNil(result.selectedLogSource)
    }

    func testOperationDetailUsesOperationStateInsteadOfLegacyProgressMessage() async {
        let status = platformState()
        let snapshots = StubStatusSnapshotLoader(
            status: status,
            operationState: PlatformOperationState(
                activeOperation: .applyBundle,
                install: .unavailable()
            )
        )
        let refresher = RuntimeStatusRefresher(snapshots: snapshots)

        let result = await refresher.operationDetail(
            settings: RuntimeSettings(),
            pendingDetail: "Waiting"
        )

        XCTAssertEqual(result.status, status)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.operationDetail, "Apply Bundle in progress")
        XCTAssertNil(result.selectedLogSource)
    }
}

@MainActor
private final class StubStatusSnapshotLoader: RuntimeStatusSnapshotLoading {
    let status: PlatformState
    let healthStatus: PlatformState
    let operationState: PlatformOperationState
    private(set) var loadStatusCount = 0
    private(set) var loadHealthStatusCount = 0
    private(set) var loadOperationStateCount = 0

    init(
        status: PlatformState = platformState(),
        healthStatus: PlatformState = platformState(),
        operationState: PlatformOperationState? = nil
    ) {
        self.status = status
        self.healthStatus = healthStatus
        self.operationState = operationState ?? PlatformOperationState(
            activeOperation: nil,
            install: .unavailable()
        )
    }

    func loadPlatformState(settings: RuntimeSettings) async -> PlatformState {
        loadStatusCount += 1
        return status
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        loadHealthStatusCount += 1
        return healthStatus
    }

    func loadOperationState() async -> PlatformOperationState {
        loadOperationStateCount += 1
        return operationState
    }
}
