import RuntimeControl
import Errors

@MainActor
public protocol RuntimeStatusSnapshotLoading {
    func loadPlatformState(settings: RuntimeSettings) async -> PlatformState
    func loadOperationState() async -> PlatformOperationState
    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState
}

public protocol RuntimeStatusPresentationFormatting {
    func statusDisplayMessage(_ status: PlatformState) -> String?
    func updateOperationDisplayMessage(_ status: PlatformState, operationState: PlatformOperationState) -> String?
}

public struct RuntimeStatusRefreshResult {
    public let status: PlatformState
    public let operationState: PlatformOperationState
    public let message: String?
    public let operationDetail: String?
    public let selectedLogSource: RuntimeLogSource?

    public init(
        status: PlatformState,
        operationState: PlatformOperationState,
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
        let status = await snapshots.loadPlatformState(settings: settings)
        let operationState = await snapshots.loadOperationState()
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: isBusy,
            includeOperationStatePresentation: true
        )
    }

    public func refreshHealthStatus(
        settings: RuntimeSettings,
        isBusy: Bool
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        let operationState = await snapshots.loadOperationState()
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: isBusy,
            includeOperationStatePresentation: true
        )
    }

    public func healthCheckStatus(
        settings: RuntimeSettings,
        completedMessage: String
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadHealthStatus(settings: settings)
        let operationState = await snapshots.loadOperationState()
        return presentation(
            status: status,
            operationState: operationState,
            isBusy: true,
            includeOperationStatePresentation: false,
            messagePrefix: completedMessage
        )
    }

    public func operationDetail(
        settings: RuntimeSettings,
        pendingDetail: String
    ) async -> RuntimeStatusRefreshResult {
        let status = await snapshots.loadPlatformState(settings: settings)
        let operationState = await snapshots.loadOperationState()
        return RuntimeStatusRefreshResult(
            status: status,
            operationState: operationState,
            message: nil,
            operationDetail: formatter.updateOperationDisplayMessage(status, operationState: operationState) ?? pendingDetail,
            selectedLogSource: nil
        )
    }

    private func presentation(
        status: PlatformState,
        operationState: PlatformOperationState,
        isBusy: Bool,
        includeOperationStatePresentation: Bool,
        messagePrefix: String? = nil
    ) -> RuntimeStatusRefreshResult {
        let displayMessage = formatter.statusDisplayMessage(status)
        var message = prefixedMessage(prefix: messagePrefix, displayMessage: displayMessage)
        var operationDetail: String?
        var selectedLogSource: RuntimeLogSource?

        if includeOperationStatePresentation,
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
