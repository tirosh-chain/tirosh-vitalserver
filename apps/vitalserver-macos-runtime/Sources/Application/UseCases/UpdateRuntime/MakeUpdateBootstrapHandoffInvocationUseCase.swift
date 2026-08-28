import Contracts
import Domain

public struct MakeUpdateBootstrapHandoffInvocationUseCase {
    public init() {}

    public func execute(
        journal: UpdateBootstrapJournal,
        guestControlBaseURL: String
    ) throws -> UpdateBootstrapHandoffInvocation {
        try UpdateBootstrapHandoffPolicy.makeInvocation(
            journal: journal,
            guestControlBaseURL: guestControlBaseURL
        )
    }
}
