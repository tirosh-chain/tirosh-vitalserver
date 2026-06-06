import Contracts

public protocol RuntimeStatusServiceValueVocabulary {
    var updatingText: String { get }
    var unavailableText: String { get }

    func launchdStateText(_ state: RuntimeServiceState) -> String
    func launchdLoadedText(_ loaded: Bool) -> String
}

public struct RuntimeStatusServiceValue: Equatable, Sendable {
    public let text: String
    public let severity: RuntimeStatusReachabilityPolicy.Severity
    public let uptimeText: String?

    public init(
        text: String,
        severity: RuntimeStatusReachabilityPolicy.Severity,
        uptimeText: String?
    ) {
        self.text = text
        self.severity = severity
        self.uptimeText = uptimeText
    }
}

public struct RuntimeStatusServiceValuePolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let vocabulary: any RuntimeStatusServiceValueVocabulary

    public init(vocabulary: any RuntimeStatusServiceValueVocabulary) {
        self.vocabulary = vocabulary
    }

    public func serviceValue(
        state: RuntimeServiceState?,
        fallbackLoaded: Bool?,
        updateInProgress: Bool = false
    ) -> RuntimeStatusServiceValue {
        if updateInProgress, reachabilityPolicy.shouldDisplayOperationStateInsteadOfServiceState(state) {
            return value(vocabulary.updatingText, .warning)
        }
        if let state {
            return value(
                vocabulary.launchdStateText(state),
                reachabilityPolicy.serviceStateSeverity(state)
            )
        }
        if let fallbackLoaded {
            return value(
                vocabulary.launchdLoadedText(fallbackLoaded),
                fallbackLoaded ? .healthy : .warning
            )
        }
        return value(vocabulary.unavailableText, .warning)
    }

    private func value(
        _ text: String,
        _ severity: RuntimeStatusReachabilityPolicy.Severity
    ) -> RuntimeStatusServiceValue {
        RuntimeStatusServiceValue(
            text: text,
            severity: severity,
            uptimeText: nil
        )
    }
}
