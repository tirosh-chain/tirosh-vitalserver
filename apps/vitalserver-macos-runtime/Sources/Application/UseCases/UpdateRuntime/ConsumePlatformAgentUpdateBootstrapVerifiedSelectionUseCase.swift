import Contracts
import Domain

public enum BindPlatformAgentUpdateBootstrapApplyError:
    Error,
    Equatable,
    Sendable
{
    case missing(path: String)
    case stale
    case conflict(expectedPath: String, actualPath: String)
    case invalid(reason: String)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case persistFailed(reason: String)
}

public struct BindPlatformAgentUpdateBootstrapApplyUseCase {
    public init() {}

    public func bind(
        observedBundlePath: String,
        mintRequestId: () -> String,
        observedAt: String,
        currentRead: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult,
        persist: (PlatformAgentUpdateBootstrapVerifiedSelection) throws -> Void
    ) throws -> String {
        let current = try requireSelection(currentRead)
        let requestId: String
        if current.state
            == PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateApplyCommitted,
            let bound = current.boundRequestId
        {
            requestId = bound
        } else {
            requestId = mintRequestId()
        }
        let committed: (
            selection: PlatformAgentUpdateBootstrapVerifiedSelection,
            persisted: Bool
        )
        do {
            committed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                .commitApply(
                    selection: current,
                    requestId: requestId,
                    observedBundlePath: observedBundlePath,
                    observedAt: observedAt
                )
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
        {
            throw mapTransition(error)
        }
        if committed.persisted {
            do {
                try persist(committed.selection)
            } catch {
                throw BindPlatformAgentUpdateBootstrapApplyError
                    .persistFailed(reason: String(describing: error))
            }
        }
        guard let bound = committed.selection.boundRequestId else {
            throw BindPlatformAgentUpdateBootstrapApplyError
                .invalid(reason: "missingField(boundRequestId)")
        }
        return bound
    }

    private func requireSelection(
        _ read: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult
    ) throws -> PlatformAgentUpdateBootstrapVerifiedSelection {
        switch read {
        case .missing(let path):
            throw BindPlatformAgentUpdateBootstrapApplyError.missing(path: path)
        case .inspectionFailed(let path, let reason):
            throw BindPlatformAgentUpdateBootstrapApplyError
                .inspectionFailed(path: path, reason: reason)
        case .permissionDenied(let path, let reason):
            throw BindPlatformAgentUpdateBootstrapApplyError
                .permissionDenied(path: path, reason: reason)
        case .readFailed(let path, let reason):
            throw BindPlatformAgentUpdateBootstrapApplyError
                .readFailed(path: path, reason: reason)
        case .decodeFailed(let path, let reason):
            throw BindPlatformAgentUpdateBootstrapApplyError
                .decodeFailed(path: path, reason: reason)
        case .unexpectedPathState(let path, let state):
            throw BindPlatformAgentUpdateBootstrapApplyError
                .unexpectedPathState(path: path, state: state)
        case .loaded(let loaded):
            return loaded
        }
    }

    private func mapTransition(
        _ error: PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
    ) -> BindPlatformAgentUpdateBootstrapApplyError {
        switch error {
        case .invalidSelection(let validation):
            return .invalid(reason: String(describing: validation))
        case .stale:
            return .stale
        case .conflict(let expectedPath, let actualPath):
            return .conflict(
                expectedPath: expectedPath,
                actualPath: actualPath
            )
        case .invalidRequestId(let value):
            return .invalid(reason: "invalidRequestId(\(value))")
        case .inFlight(let requestId):
            return .invalid(reason: "inFlight(\(requestId))")
        case .invalidCurrentState(let state, let event):
            return .invalid(reason: "invalidCurrentState(\(state), \(event))")
        case .requestMismatch(let expected, let actual):
            return .invalid(
                reason: "requestMismatch(\(expected), \(actual))"
            )
        }
    }
}

public enum SpendPlatformAgentUpdateBootstrapApplyError:
    Error,
    Equatable,
    Sendable
{
    case missing(path: String)
    case invalid(reason: String)
    case requestMismatch(expected: String, actual: String)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case persistFailed(reason: String)
}

public struct SpendPlatformAgentUpdateBootstrapApplyUseCase {
    public init() {}

    public func spend(
        requestId: String,
        observedAt: String,
        currentRead: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult,
        persist: (PlatformAgentUpdateBootstrapVerifiedSelection) throws -> Void
    ) throws {
        let current = try requireSelection(currentRead)
        let spent: (
            selection: PlatformAgentUpdateBootstrapVerifiedSelection,
            persisted: Bool
        )
        do {
            spent = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                .spend(
                    selection: current,
                    requestId: requestId,
                    observedAt: observedAt
                )
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
        {
            throw mapTransition(error)
        }
        if spent.persisted {
            do {
                try persist(spent.selection)
            } catch {
                throw SpendPlatformAgentUpdateBootstrapApplyError
                    .persistFailed(reason: String(describing: error))
            }
        }
    }

    private func requireSelection(
        _ read: PlatformAgentUpdateBootstrapVerifiedSelectionReadResult
    ) throws -> PlatformAgentUpdateBootstrapVerifiedSelection {
        switch read {
        case .missing(let path):
            throw SpendPlatformAgentUpdateBootstrapApplyError.missing(path: path)
        case .inspectionFailed(let path, let reason):
            throw SpendPlatformAgentUpdateBootstrapApplyError
                .inspectionFailed(path: path, reason: reason)
        case .permissionDenied(let path, let reason):
            throw SpendPlatformAgentUpdateBootstrapApplyError
                .permissionDenied(path: path, reason: reason)
        case .readFailed(let path, let reason):
            throw SpendPlatformAgentUpdateBootstrapApplyError
                .readFailed(path: path, reason: reason)
        case .decodeFailed(let path, let reason):
            throw SpendPlatformAgentUpdateBootstrapApplyError
                .decodeFailed(path: path, reason: reason)
        case .unexpectedPathState(let path, let state):
            throw SpendPlatformAgentUpdateBootstrapApplyError
                .unexpectedPathState(path: path, state: state)
        case .loaded(let loaded):
            return loaded
        }
    }

    private func mapTransition(
        _ error: PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
    ) -> SpendPlatformAgentUpdateBootstrapApplyError {
        switch error {
        case .requestMismatch(let expected, let actual):
            return .requestMismatch(expected: expected, actual: actual)
        case .invalidSelection(let validation):
            return .invalid(reason: String(describing: validation))
        case .invalidCurrentState(let state, let event):
            return .invalid(reason: "invalidCurrentState(\(state), \(event))")
        case .invalidRequestId(let value):
            return .invalid(reason: "invalidRequestId(\(value))")
        default:
            return .invalid(reason: String(describing: error))
        }
    }
}
