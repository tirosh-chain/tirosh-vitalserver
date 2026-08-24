import Contracts
import Domain

public enum InvokePlatformAgentUpdateBootstrapVerificationError:
    Error,
    Equatable,
    Sendable
{
    case invalidVerificationInvocationId(String)
    case invalidBundlePath(String)
    case invalidObservedAt(String)
    case evidencePersistFailed(reason: String)
}

public struct InvokePlatformAgentUpdateBootstrapVerificationUseCase {
    public init() {}

    public func invoke(
        verificationInvocationId: String,
        bundlePath: String,
        observedAt: String,
        persist: (PlatformAgentUpdateBootstrapVerificationEvidence) throws ->
            Void,
        spawn: (String) async ->
            PlatformAgentUpdateBootstrapVerificationSpawnResult,
        bindingRead: (String) ->
            UpdateBootstrapVerificationInvocationBindingReadResult
    ) async throws -> PlatformAgentUpdateBootstrapVerificationOutcome {
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            verificationInvocationId
        ) else {
            throw InvokePlatformAgentUpdateBootstrapVerificationError
                .invalidVerificationInvocationId(verificationInvocationId)
        }
        let invoked = PlatformAgentUpdateBootstrapVerificationPolicy.invoked(
            verificationInvocationId: verificationInvocationId,
            bundlePath: bundlePath,
            observedAt: observedAt
        )
        do {
            try PlatformAgentUpdateBootstrapVerificationPolicy.validate(invoked)
        } catch let error as
            PlatformAgentUpdateBootstrapVerificationValidationError
        {
            switch error {
            case .invalidBundlePath(let path):
                throw InvokePlatformAgentUpdateBootstrapVerificationError
                    .invalidBundlePath(path)
            case .invalidObservedAt(let value):
                throw InvokePlatformAgentUpdateBootstrapVerificationError
                    .invalidObservedAt(value)
            default:
                throw InvokePlatformAgentUpdateBootstrapVerificationError
                    .evidencePersistFailed(reason: String(describing: error))
            }
        }
        do {
            try persist(invoked)
        } catch {
            throw InvokePlatformAgentUpdateBootstrapVerificationError
                .evidencePersistFailed(reason: String(describing: error))
        }

        let outcome = PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
            spawn: await spawn(verificationInvocationId),
            expectedVerificationInvocationId: verificationInvocationId,
            bindingRead: bindingRead(verificationInvocationId)
        )
        let completed = PlatformAgentUpdateBootstrapVerificationPolicy.evidence(
            from: invoked,
            outcome: outcome
        )
        do {
            try persist(completed)
        } catch {
            throw InvokePlatformAgentUpdateBootstrapVerificationError
                .evidencePersistFailed(reason: String(describing: error))
        }
        return outcome
    }
}
