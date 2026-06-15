import Errors
public protocol RuntimeStatusHTTPValueVocabulary: RuntimeStatusReachabilityLabelVocabulary {
    var installingText: String { get }
    var initializingText: String { get }
    var updatingText: String { get }
    var recoveringText: String { get }
}

public struct RuntimeStatusHTTPValue: Equatable, Sendable {
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

public struct RuntimeStatusHTTPValuePolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let labelPolicy: RuntimeStatusReachabilityLabelPolicy
    private let vocabulary: any RuntimeStatusHTTPValueVocabulary

    public init(vocabulary: any RuntimeStatusHTTPValueVocabulary) {
        self.vocabulary = vocabulary
        self.labelPolicy = RuntimeStatusReachabilityLabelPolicy(vocabulary: vocabulary)
    }

    public func serviceValue(
        httpStatus: String?,
        uptimeText: String?,
        installInProgress: Bool = false,
        initializationInProgress: Bool = false,
        recoveryInProgress: Bool = false,
        updateInProgress: Bool = false
    ) -> RuntimeStatusHTTPValue {
        if installInProgress {
            return installingValue(uptimeText: uptimeText)
        }
        if initializationInProgress {
            return initializingValue(uptimeText: uptimeText)
        }
        if recoveryInProgress {
            return recoveringValue(uptimeText: uptimeText)
        }
        if updateInProgress {
            return updatingValue(uptimeText: uptimeText)
        }
        return httpValue(httpStatus, uptimeText: uptimeText)
    }

    public func httpValue(_ status: String?, uptimeText: String?) -> RuntimeStatusHTTPValue {
        RuntimeStatusHTTPValue(
            text: labelPolicy.serviceReachabilityLabel(status),
            severity: reachabilityPolicy.httpSeverity(status),
            uptimeText: uptimeText
        )
    }

    public func installingValue(uptimeText: String?) -> RuntimeStatusHTTPValue {
        RuntimeStatusHTTPValue(
            text: vocabulary.installingText,
            severity: .warning,
            uptimeText: uptimeText
        )
    }

    public func initializingValue(uptimeText: String?) -> RuntimeStatusHTTPValue {
        RuntimeStatusHTTPValue(
            text: vocabulary.initializingText,
            severity: .warning,
            uptimeText: uptimeText
        )
    }

    public func updatingValue(uptimeText: String?) -> RuntimeStatusHTTPValue {
        RuntimeStatusHTTPValue(
            text: vocabulary.updatingText,
            severity: .warning,
            uptimeText: uptimeText
        )
    }

    public func recoveringValue(uptimeText: String?) -> RuntimeStatusHTTPValue {
        RuntimeStatusHTTPValue(
            text: vocabulary.recoveringText,
            severity: .warning,
            uptimeText: uptimeText
        )
    }
}
