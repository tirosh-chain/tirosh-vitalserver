import Contracts
import Domain

public struct AuthorizeRuntimeUpdateApplyInput: Equatable, Sendable {
    public let installedChannel: UpdateBundleChannel
    public let trustIntent: RuntimeUpdateApplyTrustIntent

    public init(
        installedChannel: UpdateBundleChannel,
        trustIntent: RuntimeUpdateApplyTrustIntent
    ) {
        self.installedChannel = installedChannel
        self.trustIntent = trustIntent
    }
}

public struct AuthorizeRuntimeUpdateApplyUseCase {
    public init() {}

    public func authorize(
        input: AuthorizeRuntimeUpdateApplyInput
    ) throws -> RuntimeUpdateApplyTrustDecision {
        try RuntimeUpdateApplyTrustPolicy.authorize(
            installedChannel: input.installedChannel,
            intent: input.trustIntent
        )
    }
}
