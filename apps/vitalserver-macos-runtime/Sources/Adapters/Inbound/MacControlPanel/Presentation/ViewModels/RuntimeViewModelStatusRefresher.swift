import RuntimeControl
import Errors

@MainActor
public protocol RuntimeViewModelStatusSnapshotLoading {
    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

public protocol RuntimeViewModelStatusPresentationFormatting {
    func statusDisplayMessage(_ status: RuntimeStatus) -> String?
    func updateOperationDisplayMessage(_ status: RuntimeStatus) -> String?
    func progressDisplayMessage(_ status: RuntimeStatus) -> String?
}

public struct RuntimeViewModelStatusRefreshResult {
    public let status: RuntimeStatus
    public let message: String?
    public let operationDetail: String?
    public let selectedLogSource: RuntimeLogSource?

    public init(
        status: RuntimeStatus,
        message: String?,
        operationDetail: String?,
        selectedLogSource: RuntimeLogSource?
    ) {
        self.status = status
        self.message = message
        self.operationDetail = operationDetail
        self.selectedLogSource = selectedLogSource
    }
}

@MainActor
public struct RuntimeViewModelStatusRefresher {
    private let snapshots: any RuntimeViewModelStatusSnapshotLoading
    private let formatter: any RuntimeViewModelStatusPresentationFormatting

    public init(
        snapshots: any RuntimeViewModelStatusSnapshotLoading,
        formatter: any RuntimeViewModelStatusPresentationFormatting
    ) {
        self.snapshots = snapshots
        self.formatter = formatter
    }

    public func refreshStatus(
        settings: RuntimeSettings,
        isBusy: Bool
    ) async -> RuntimeViewModelStatusRefreshResult {
        let status = await snapshots.loadStatus(settings: settings)
        return presentation(
            status: status,
            isBusy: isBusy,
            synchronizeFileBackedOperation: true
        )
    }

    public func refreshHealthStatus(
        settings: RuntimeSettings,
        isBusy: Bool
    ) async -> RuntimeViewModelStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        return presentation(
            status: status,
            isBusy: isBusy,
            synchronizeFileBackedOperation: true
        )
    }

    public func healthCheckStatus(
        settings: RuntimeSettings,
        completedMessage: String
    ) async -> RuntimeViewModelStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        return presentation(
            status: status,
            isBusy: true,
            synchronizeFileBackedOperation: false,
            messagePrefix: completedMessage
        )
    }

    public func operationDetail(
        settings: RuntimeSettings,
        pendingDetail: String
    ) async -> RuntimeViewModelStatusRefreshResult {
        let status = await snapshots.loadStatus(settings: settings)
        return RuntimeViewModelStatusRefreshResult(
            status: status,
            message: nil,
            operationDetail: formatter.progressDisplayMessage(status) ?? pendingDetail,
            selectedLogSource: nil
        )
    }

    private func presentation(
        status: RuntimeStatus,
        isBusy: Bool,
        synchronizeFileBackedOperation: Bool,
        messagePrefix: String? = nil
    ) -> RuntimeViewModelStatusRefreshResult {
        let displayMessage = formatter.statusDisplayMessage(status)
        var message = prefixedMessage(prefix: messagePrefix, displayMessage: displayMessage)
        var operationDetail: String?
        var selectedLogSource: RuntimeLogSource?

        if synchronizeFileBackedOperation,
           !isBusy,
           let updateMessage = formatter.updateOperationDisplayMessage(status) {
            selectedLogSource = .command
            message = updateMessage
            operationDetail = updateMessage
        }

        return RuntimeViewModelStatusRefreshResult(
            status: status,
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

extension RuntimeViewModelSnapshotLoader: RuntimeViewModelStatusSnapshotLoading {}
extension RuntimePresentationFormatter: RuntimeViewModelStatusPresentationFormatting {}

extension RuntimeViewModelStatusRefresher {
    init(
        snapshots: any RuntimeViewModelStatusSnapshotLoading,
        formatter: RuntimePresentationFormatter = RuntimePresentationFormatter()
    ) {
        self.init(snapshots: snapshots, formatter: formatter as any RuntimeViewModelStatusPresentationFormatting)
    }
}
