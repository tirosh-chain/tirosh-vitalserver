import Contracts
import RuntimeControl
import Errors

public protocol RuntimeStatusActionNeededVocabulary {
    var runtimeNotInstalledTitle: String { get }
    var installAction: String { get }
    var vitalServerNeedsAttentionTitle: String { get }
    var openLogsAction: String { get }
    var vitalServerUnavailableTitle: String { get }

    func domainRecoveryActionText(_ action: RuntimeDomainRecoveryAction) -> String
}

public enum RuntimeStatusActionNeededSeverity: Equatable, Sendable {
    case warning
    case critical
}

public struct RuntimeStatusActionNeededDecision: Equatable, Sendable {
    public let title: String
    public let recommendedAction: String
    public let severity: RuntimeStatusActionNeededSeverity

    public init(
        title: String,
        recommendedAction: String,
        severity: RuntimeStatusActionNeededSeverity
    ) {
        self.title = title
        self.recommendedAction = recommendedAction
        self.severity = severity
    }
}

public struct RuntimeStatusActionNeededPolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let vocabulary: any RuntimeStatusActionNeededVocabulary

    public init(vocabulary: any RuntimeStatusActionNeededVocabulary) {
        self.vocabulary = vocabulary
    }

    public func actionNeeded(status: RuntimeStatus) -> RuntimeStatusActionNeededDecision? {
        if RuntimeReadinessPolicy.isReady(status) || isManagedOperationInProgress(status.runtimeState) {
            return nil
        }
        if !status.runtimeInstalled {
            return RuntimeStatusActionNeededDecision(
                title: vocabulary.runtimeNotInstalledTitle,
                recommendedAction: vocabulary.installAction,
                severity: .critical
            )
        }

        let primaryReason = status.failureReasons.first { $0.domainSeverity == .critical }
            ?? status.failureReasons.first
        if let primaryReason {
            return RuntimeStatusActionNeededDecision(
                title: userFacingProblemTitle(status),
                recommendedAction: userFacingAction(for: primaryReason.recoveryAction),
                severity: primaryReason.domainSeverity == .critical ? .critical : .warning
            )
        }
        if !status.readIssues.isEmpty {
            return RuntimeStatusActionNeededDecision(
                title: vocabulary.vitalServerNeedsAttentionTitle,
                recommendedAction: vocabulary.openLogsAction,
                severity: .warning
            )
        }
        return nil
    }

    private func isManagedOperationInProgress(_ state: RuntimeState?) -> Bool {
        state == .installing || state == .updating || state == .recovering
    }

    private func userFacingProblemTitle(_ status: RuntimeStatus) -> String {
        if !reachabilityPolicy.isSuccessfulHTTPStatus(status.guestHTTP)
            || !reachabilityPolicy.isSuccessfulHTTPStatus(status.hostProxyHTTP) {
            return vocabulary.vitalServerUnavailableTitle
        }
        return vocabulary.vitalServerNeedsAttentionTitle
    }

    private func userFacingAction(for action: RuntimeDomainRecoveryAction) -> String {
        switch action {
        case .installRuntime:
            return vocabulary.installAction
        default:
            return vocabulary.domainRecoveryActionText(action)
        }
    }
}
