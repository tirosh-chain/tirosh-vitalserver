import Contracts
import Errors

public protocol RuntimeStatusServiceValueVocabulary {
    var installingText: String { get }
    var updatingText: String { get }
    var unavailableText: String { get }

    func launchdStateText(_ state: RuntimeServiceState) -> String
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
    private let serviceStatePolicy = RuntimeStatusServiceStatePresentationPolicy()
    private let vocabulary: any RuntimeStatusServiceValueVocabulary

    public init(vocabulary: any RuntimeStatusServiceValueVocabulary) {
        self.vocabulary = vocabulary
    }

    public func serviceValue(
        state: RuntimeServiceState?,
        installInProgress: Bool = false,
        updateInProgress: Bool = false
    ) -> RuntimeStatusServiceValue {
        if installInProgress, serviceStatePolicy.shouldDisplayOperationStateInsteadOfServiceState(state) {
            return value(vocabulary.installingText, .warning)
        }
        if updateInProgress, serviceStatePolicy.shouldDisplayOperationStateInsteadOfServiceState(state) {
            return value(vocabulary.updatingText, .warning)
        }
        if let state {
            return value(
                vocabulary.launchdStateText(state),
                serviceStatePolicy.serviceStateSeverity(state)
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
