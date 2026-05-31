import RuntimeControl

@MainActor
protocol RuntimeViewModelStatusSnapshotLoading {
    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

extension RuntimeViewModelSnapshotLoader: RuntimeViewModelStatusSnapshotLoading {}

struct RuntimeViewModelStatusRefreshResult {
    let status: RuntimeStatus
    let message: String?
    let operationDetail: String?
    let selectedLogSource: RuntimeLogSource?
}

@MainActor
struct RuntimeViewModelStatusRefresher {
    private let snapshots: any RuntimeViewModelStatusSnapshotLoading
    private let formatter: RuntimePresentationFormatter

    init(
        snapshots: any RuntimeViewModelStatusSnapshotLoading,
        formatter: RuntimePresentationFormatter = RuntimePresentationFormatter()
    ) {
        self.snapshots = snapshots
        self.formatter = formatter
    }

    func refreshStatus(
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

    func refreshHealthStatus(
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

    func healthCheckStatus(
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

    func operationDetail(
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
