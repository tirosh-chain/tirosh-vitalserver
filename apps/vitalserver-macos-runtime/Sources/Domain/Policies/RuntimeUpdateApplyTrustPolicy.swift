import Contracts

public enum RuntimeUpdateApplyTrustDecision: Equatable, Sendable {
    case allowUnsignedDevelopmentBundle

    public var logMessage: String {
        switch self {
        case .allowUnsignedDevelopmentBundle:
            return "update apply trust override accepted installedChannel=dev publisherAuthenticity=unverified scope=local-development"
        }
    }
}

public enum RuntimeUpdateApplyTrustPolicy {
    public static func authorize(
        installedChannel: UpdateBundleChannel,
        intent: RuntimeUpdateApplyTrustIntent
    ) throws -> RuntimeUpdateApplyTrustDecision {
        switch intent {
        case .requireVerifiedPublisher:
            throw RuntimeUpdateApplyTrustError.publisherVerificationUnavailable(
                installedChannel: installedChannel
            )
        case .allowUnsignedDevelopmentBundle:
            guard installedChannel == .dev else {
                throw RuntimeUpdateApplyTrustError.unsignedDevelopmentIntentNotAllowed(
                    installedChannel: installedChannel
                )
            }
            return .allowUnsignedDevelopmentBundle
        }
    }
}
