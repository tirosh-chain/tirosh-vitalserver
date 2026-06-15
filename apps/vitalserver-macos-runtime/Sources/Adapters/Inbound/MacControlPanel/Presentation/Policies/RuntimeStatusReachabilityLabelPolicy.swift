import Errors
public protocol RuntimeStatusReachabilityLabelVocabulary {
    var notReportedText: String { get }
    var reachableText: String { get }
    var unavailableText: String { get }
    var unreachableText: String { get }
    var failedText: String { get }
}

public struct RuntimeStatusReachabilityLabelPolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let vocabulary: any RuntimeStatusReachabilityLabelVocabulary

    public init(vocabulary: any RuntimeStatusReachabilityLabelVocabulary) {
        self.vocabulary = vocabulary
    }

    public func serviceReachabilityLabel(_ value: String?) -> String {
        switch reachabilityPolicy.reachability(value) {
        case .notReported:
            return vocabulary.notReportedText
        case .reachable:
            return vocabulary.reachableText
        case .unavailable:
            return vocabulary.unavailableText
        case .unreachable:
            return vocabulary.unreachableText
        case .failed:
            return vocabulary.failedText
        }
    }
}
