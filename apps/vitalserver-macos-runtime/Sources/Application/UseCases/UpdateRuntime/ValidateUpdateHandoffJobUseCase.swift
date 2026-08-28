import Contracts
import Domain

public struct ValidateUpdateHandoffJobUseCase {
    public init() {}

    public func validate(_ job: UpdateHandoffJobDocument) throws {
        try UpdateHandoffJobStateMachine.validate(job)
    }
}
