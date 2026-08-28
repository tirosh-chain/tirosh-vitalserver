import Contracts
import Foundation

public enum PlatformAgentUpdateBootstrapVerifiedSelectionReadResult:
    Equatable,
    Sendable
{
    case missing(path: String)
    case loaded(PlatformAgentUpdateBootstrapVerifiedSelection)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}

public protocol PlatformAgentUpdateBootstrapVerifiedSelectionReading {
    func read(
        at url: URL
    ) -> PlatformAgentUpdateBootstrapVerifiedSelectionReadResult
}

public protocol PlatformAgentUpdateBootstrapVerifiedSelectionWriting {
    func write(
        _ selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        to destination: URL
    ) throws
}
