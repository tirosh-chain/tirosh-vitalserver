import Contracts

/// Host application port to the Guest-owned immutable Runtime release state.
public protocol RuntimeGuestReleaseGateway {
    func activeGuestRelease() throws -> RuntimeGuestReleaseRead
    func applyGuestRelease(
        _ request: RuntimeGuestReleaseMutationRequest
    ) throws -> RuntimeGuestReleaseOperation
    func rollbackGuestRelease(
        _ request: RuntimeGuestReleaseMutationRequest
    ) throws -> RuntimeGuestReleaseOperation
    func guestReleaseOperation(
        _ operationId: String
    ) throws -> RuntimeGuestReleaseOperation
}
