import Contracts
import Errors

public protocol RuntimeStatusVMStateVocabulary {
    func vmStateText(_ value: RuntimeVMState?) -> String
}

public struct RuntimeStatusVMStateValue: Equatable, Sendable {
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

public struct RuntimeStatusVMStatePolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let vocabulary: any RuntimeStatusVMStateVocabulary

    public init(vocabulary: any RuntimeStatusVMStateVocabulary) {
        self.vocabulary = vocabulary
    }

    public func vmStateValue(_ value: RuntimeVMState?) -> RuntimeStatusVMStateValue {
        RuntimeStatusVMStateValue(
            text: vocabulary.vmStateText(value),
            severity: reachabilityPolicy.vmStateSeverity(value),
            uptimeText: nil
        )
    }
}
