import Contracts
import Domain

public struct AdmitUpdateBootstrapUseCase {
    public init() {}

    public func admit(
        envelope: UpdateBootstrapEnvelope,
        verification: VerifiedUpdateBootstrapClosure,
        operationId: String,
        installedRelease: InstalledProductRelease,
        requestId: String,
        admittedAt: String,
        platformAgentSelectionCorrelation:
            UpdateBootstrapPlatformAgentSelectionCorrelation? = nil
    ) throws -> UpdateBootstrapJournal {
        try UpdateBootstrapAdmissionPolicy.admit(
            envelope: envelope,
            verification: verification,
            operationId: operationId,
            installedRelease: installedRelease,
            requestId: requestId,
            admittedAt: admittedAt,
            platformAgentSelectionCorrelation:
                platformAgentSelectionCorrelation
        )
    }
}
