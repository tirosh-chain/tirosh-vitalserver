import Contracts
import Foundation

public enum PlatformAgentUpdateBootstrapVerificationEvidenceReadResult:
    Equatable,
    Sendable
{
    case missing(path: String)
    case loaded(PlatformAgentUpdateBootstrapVerificationEvidence)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}

public protocol PlatformAgentUpdateBootstrapVerificationEvidenceReading {
    func read(
        at url: URL
    ) -> PlatformAgentUpdateBootstrapVerificationEvidenceReadResult
}

public protocol PlatformAgentUpdateBootstrapVerificationEvidenceWriting {
    func write(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence,
        to destination: URL
    ) throws
}
