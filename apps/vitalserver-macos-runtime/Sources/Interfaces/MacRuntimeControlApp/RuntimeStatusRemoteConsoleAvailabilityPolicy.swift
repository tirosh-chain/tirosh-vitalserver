import Foundation
import RuntimeControl

public protocol RuntimeStatusRemoteConsoleAvailabilityVocabulary {
    var reachableText: String { get }
    var unavailableText: String { get }
}

public struct RuntimeStatusRemoteConsoleAvailabilityValue: Equatable, Sendable {
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

public struct RuntimeStatusRemoteConsoleAvailabilityPolicy {
    private let uptimeFormatter = RuntimeStatusUptimeFormatter()
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let vocabulary: any RuntimeStatusRemoteConsoleAvailabilityVocabulary

    public init(vocabulary: any RuntimeStatusRemoteConsoleAvailabilityVocabulary) {
        self.vocabulary = vocabulary
    }

    public func availability(
        status: RuntimeStatus,
        now: Date = Date()
    ) -> RuntimeStatusRemoteConsoleAvailabilityValue {
        availability(
            http: status.runtimeControlHTTP,
            startedAt: status.runtimeControlStartedAt,
            now: now
        )
    }

    public func availability(
        http: String?,
        startedAt: String?,
        now: Date = Date()
    ) -> RuntimeStatusRemoteConsoleAvailabilityValue {
        let reachable = reachabilityPolicy.isSuccessfulHTTPStatus(http)
        return RuntimeStatusRemoteConsoleAvailabilityValue(
            text: reachable ? vocabulary.reachableText : vocabulary.unavailableText,
            severity: reachable ? .healthy : .warning,
            uptimeText: uptimeFormatter.formatUptime(
                seconds: nil,
                startedAt: startedAt,
                observedAt: nil,
                now: now
            )
        )
    }
}
