import Contracts
import Domain

public enum RecordPlatformAgentUpdateBootstrapVerifiedSelectionError:
    Error,
    Equatable,
    Sendable
{
    case invalidSelectionId(String)
    case invalidVerificationInvocationId(String)
    case invalidUpdateId(String)
    case invalidCanonicalPayloadSHA256(String)
    case invalidObservedBundlePath(String)
    case invalidObservedAt(String)
    case persistFailed(reason: String)
    case inFlight(requestId: String)
    case missing(path: String)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case invalid(reason: String)
}

public struct RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase {
    public init() {}

    public func record(
        selectionId: String,
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        observedBundlePath: String,
        observedAt: String,
        currentRead: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult,
        persist: (PlatformAgentUpdateBootstrapVerifiedSelection) throws -> Void
    ) throws -> PlatformAgentUpdateBootstrapVerifiedSelection {
        let next = PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .verified(
                selectionId: selectionId,
                verificationInvocationId: verificationInvocationId,
                updateId: updateId,
                canonicalPayloadSHA256: canonicalPayloadSHA256,
                observedBundlePath: observedBundlePath,
                observedAt: observedAt
            )
        let current = try optionalCurrent(currentRead)
        let selected: PlatformAgentUpdateBootstrapVerifiedSelection
        do {
            selected = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                .replace(current: current, with: next)
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
        {
            throw mapTransition(error)
        }
        do {
            try persist(selected)
        } catch {
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .persistFailed(reason: String(describing: error))
        }
        return selected
    }

    private func optionalCurrent(
        _ read: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult
    ) throws -> PlatformAgentUpdateBootstrapVerifiedSelection? {
        switch read {
        case .missing:
            return nil
        case .loaded(let loaded):
            return loaded
        case .inspectionFailed(let path, let reason):
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .inspectionFailed(path: path, reason: reason)
        case .permissionDenied(let path, let reason):
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .permissionDenied(path: path, reason: reason)
        case .readFailed(let path, let reason):
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .readFailed(path: path, reason: reason)
        case .decodeFailed(let path, let reason):
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .decodeFailed(path: path, reason: reason)
        case .unexpectedPathState(let path, let state):
            throw RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
                .unexpectedPathState(path: path, state: state)
        }
    }

    private func mapTransition(
        _ error: PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
    ) -> RecordPlatformAgentUpdateBootstrapVerifiedSelectionError {
        switch error {
        case .invalidSelection(let validation):
            return mapValidation(validation)
        case .inFlight(let requestId):
            return .inFlight(requestId: requestId)
        case .invalidCurrentState(let state, let event):
            return .invalid(reason: "invalidCurrentState(\(state), \(event))")
        default:
            return .invalid(reason: String(describing: error))
        }
    }

    private func mapValidation(
        _ error: PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
    ) -> RecordPlatformAgentUpdateBootstrapVerifiedSelectionError {
        switch error {
        case .invalidSelectionId(let value):
            return .invalidSelectionId(value)
        case .invalidVerificationInvocationId(let value):
            return .invalidVerificationInvocationId(value)
        case .invalidUpdateId(let value):
            return .invalidUpdateId(value)
        case .invalidCanonicalPayloadSHA256(let value):
            return .invalidCanonicalPayloadSHA256(value)
        case .invalidObservedBundlePath(let value):
            return .invalidObservedBundlePath(value)
        case .invalidObservedAt(let value):
            return .invalidObservedAt(value)
        default:
            return .invalid(reason: String(describing: error))
        }
    }
}
