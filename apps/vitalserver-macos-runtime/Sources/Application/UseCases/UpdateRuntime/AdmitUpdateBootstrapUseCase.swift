import Contracts
import Domain

public struct AdmitUpdateBootstrapUseCase {
    public init() {}

    public func admit(
        envelope: UpdateBootstrapEnvelope,
        verification: VerifiedUpdateBootstrapClosure,
        operationId: String,
        requestId: String,
        admittedAt: String
    ) throws -> UpdateBootstrapJournal {
        try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: verification,
            operationId: operationId,
            requestId: requestId,
            admittedAt: admittedAt
        )
    }
}
