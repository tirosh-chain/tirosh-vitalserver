import Contracts

/// Explicit Host application port to the Guest-owned container image-set state.
public protocol RuntimeContainerImageSetGateway {
    func currentContainerImageSet() throws -> RuntimeContainerImageSetRead
    func applyContainerImageSet(
        _ request: RuntimeContainerImageSetMutationRequest
    ) throws -> RuntimeContainerImageSetOperation
    func rollbackContainerImageSet(
        _ request: RuntimeContainerImageSetMutationRequest
    ) throws -> RuntimeContainerImageSetOperation
    func containerImageSetOperation(
        _ operationId: String
    ) throws -> RuntimeContainerImageSetOperation
}

public enum RuntimeContainerImageSetGatewayCapabilityError: Error, Equatable {
    case unavailable
}
