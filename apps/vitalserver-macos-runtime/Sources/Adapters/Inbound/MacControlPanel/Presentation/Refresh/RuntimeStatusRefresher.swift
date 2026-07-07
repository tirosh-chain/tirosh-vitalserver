import RuntimeControl
import Errors

@MainActor
public protocol RuntimeStatusSnapshotLoading {
    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadOperationState(status: RuntimeStatus) async -> RuntimeOperationState
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

public protocol RuntimeStatusPresentationFormatting {
    func statusDisplayMessage(_ status: RuntimeStatus) -> String?
    func updateOperationDisplayMessage(_ status: RuntimeStatus, operationState: RuntimeOperationState) -> String?
    func progressDisplayMessage(_ status: RuntimeStatus) -> String?
}

public struct RuntimeStatusRefreshResult {
    public let status: RuntimeStatus
    public let operationState: RuntimeOperationState
    public let message: String?
    public let operationDetail: String?
    public let selectedLogSource: RuntimeLogSource?

    public init(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        message: String?,
        operationDetail: String?,
        selectedLogSource: RuntimeLogSource?
    ) {
        self.status = status
        self.operationState = operationState
        self.message = message
        self.operationDetail = operationDetail
        self.selectedLogSource = selectedLogSource
    }
}

@MainActor
public struct RuntimeStatusRefresher {
    private let snapshots: any RuntimeStatusSnapshotLoading
    private let formatter: any RuntimeStatusPresentationFormatting

    public init(
        snapshots: any RuntimeStatusSnapshotLoading,
        formatter: any RuntimeStatusPresentationFormatting
    ) {
        self.snapshots = snapshots
        self.formatter = formatter
    }

    public func refreshStatus(
        settings: RuntimeSettings,
        isBusy: Bool
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadStatus(settings: settings)
        let operationState = await snapshots.loadOperationState(status: status)
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: isBusy,
            synchronizeFileBackedOperation: true
        )
    }

    public func refreshHealthStatus(
        settings: RuntimeSettings,
        isBusy: Bool
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        let operationState = await snapshots.loadOperationState(status: status)
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: isBusy,
            synchronizeFileBackedOperation: true
        )
    }

    public func healthCheckStatus(
        settings: RuntimeSettings,
        completedMessage: String
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        let operationState = await snapshots.loadOperationState(status: status)
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: true,
            synchronizeFileBackedOperation: false,
            messagePrefix: completedMessage
        )
    }

    public func operationDetail(
        settings: RuntimeSettings,
        pendingDetail: String
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadStatus(settings: settings)
        let operationState = await snapshots.loadOperationState(status: status)
        return RuntimeStatusRefreshResult(
            status: status,
            operationState: operationState,
            message: nil,
            operationDetail: formatter.progressDisplayMessage(status) ?? pendingDetail,
            selectedLogSource: nil
        )
    }

    private func presentation(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        isBusy: Bool,
        synchronizeFileBackedOperation: Bool,
        messagePrefix: String? = nil
    ) -> RuntimeStatusRefreshResult {
        let displayMessage = formatter.statusDisplayMessage(status)
        var message = prefixedMessage(prefix: messagePrefix, displayMessage: displayMessage)
        var operationDetail: String?
        var selectedLogSource: RuntimeLogSource?

        if synchronizeFileBackedOperation,
           !isBusy,
           let updateMessage = formatter.updateOperationDisplayMessage(status, operationState: operationState) {
            selectedLogSource = .command
            message = updateMessage
            operationDetail = updateMessage
        }

        return RuntimeStatusRefreshResult(
            status: status,
            operationState: operationState,
            message: message,
            operationDetail: operationDetail,
            selectedLogSource: selectedLogSource
        )
    }

    private func prefixedMessage(prefix: String?, displayMessage: String?) -> String? {
        guard let prefix else {
            return displayMessage
        }
        guard let displayMessage else {
            return prefix
        }
        return "\(prefix)\n\n\(displayMessage)"
    }
}

extension RuntimePresentationSnapshotLoader: RuntimeStatusSnapshotLoading {}
extension RuntimePresentationFormatter: RuntimeStatusPresentationFormatting {}

extension RuntimeStatusRefresher {
    init(
        snapshots: any RuntimeStatusSnapshotLoading,
        formatter: RuntimePresentationFormatter = RuntimePresentationFormatter()
    ) {
        self.init(snapshots: snapshots, formatter: formatter as any RuntimeStatusPresentationFormatting)
    }
}
