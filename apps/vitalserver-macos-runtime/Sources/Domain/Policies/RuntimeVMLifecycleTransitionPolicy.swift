import Contracts

public enum RuntimeVMLifecycleTransitionError: Error, Equatable, CustomStringConvertible {
    case invalidField(field: String, value: String)
    case missingCurrentState
    case alreadyExists(revision: Int)
    case staleRevision(expected: Int, actual: Int)
    case runIDMismatch(expected: String, actual: String)
    case operationIDMismatch(expected: String, actual: String)
    case operationMismatch(expected: String, actual: String)
    case startedAtMismatch(expected: String, actual: String)
    case invalidTransition(from: String, to: String)

    public var description: String {
        switch self {
        case .invalidField(let field, let value):
            return "VM lifecycle field is invalid field=\(field) value=\(value)"
        case .missingCurrentState:
            return "VM lifecycle current state is missing"
        case .alreadyExists(let revision):
            return "VM lifecycle state already exists revision=\(revision)"
        case .staleRevision(let expected, let actual):
            return "VM lifecycle revision is stale expected=\(expected) actual=\(actual)"
        case .runIDMismatch(let expected, let actual):
            return "VM lifecycle run ID mismatch expected=\(expected) actual=\(actual)"
        case .operationIDMismatch(let expected, let actual):
            return "VM lifecycle operation ID mismatch expected=\(expected) actual=\(actual)"
        case .operationMismatch(let expected, let actual):
            return "VM lifecycle operation mismatch expected=\(expected) actual=\(actual)"
        case .startedAtMismatch(let expected, let actual):
            return "VM lifecycle startedAt mismatch expected=\(expected) actual=\(actual)"
        case .invalidTransition(let from, let to):
            return "VM lifecycle transition is invalid from=\(from) to=\(to)"
        }
    }
}

public struct RuntimeVMLifecycleTransitionPolicy: Sendable {
    public init() {}

    public func nextRevision(
        current: RuntimeVMLifecycleDocument?,
        currentRevision: Int?,
        proposed: RuntimeVMLifecycleDocument,
        expectedRevision: Int?
    ) throws -> Int {
        try validateDocument(proposed)
        guard (current == nil) == (currentRevision == nil) else {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "currentState",
                value: "document/revision pair is incomplete"
            )
        }

        if proposed.state == .starting {
            return try beginRun(
                current: current,
                currentRevision: currentRevision,
                proposed: proposed,
                expectedRevision: expectedRevision
            )
        }

        guard let current, let currentRevision else {
            throw RuntimeVMLifecycleTransitionError.missingCurrentState
        }
        guard let expectedRevision else {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "expectedRevision",
                value: "missing"
            )
        }
        guard expectedRevision == currentRevision else {
            throw RuntimeVMLifecycleTransitionError.staleRevision(
                expected: expectedRevision,
                actual: currentRevision
            )
        }
        try validateIdentity(current: current, proposed: proposed)
        guard isAllowedTransition(from: current.state, to: proposed.state) else {
            throw RuntimeVMLifecycleTransitionError.invalidTransition(
                from: current.state.rawValue,
                to: proposed.state.rawValue
            )
        }
        return currentRevision + 1
    }

    private func beginRun(
        current: RuntimeVMLifecycleDocument?,
        currentRevision: Int?,
        proposed: RuntimeVMLifecycleDocument,
        expectedRevision: Int?
    ) throws -> Int {
        guard proposed.startedAt == proposed.updatedAt else {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "startedAt",
                value: proposed.startedAt
            )
        }
        switch (current, currentRevision, expectedRevision) {
        case (nil, nil, nil):
            return 1
        case (nil, nil, .some):
            throw RuntimeVMLifecycleTransitionError.missingCurrentState
        case (.some, .some(let currentRevision), nil):
            throw RuntimeVMLifecycleTransitionError.alreadyExists(revision: currentRevision)
        case (.some(let current), .some(let currentRevision), .some(let expectedRevision)):
            guard expectedRevision == currentRevision else {
                throw RuntimeVMLifecycleTransitionError.staleRevision(
                    expected: expectedRevision,
                    actual: currentRevision
                )
            }
            guard current.state == .stopped || current.state == .failed else {
                throw RuntimeVMLifecycleTransitionError.invalidTransition(
                    from: current.state.rawValue,
                    to: proposed.state.rawValue
                )
            }
            guard current.bootID != proposed.bootID else {
                throw RuntimeVMLifecycleTransitionError.invalidField(
                    field: "bootID",
                    value: proposed.bootID ?? "missing"
                )
            }
            return currentRevision + 1
        default:
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "currentState",
                value: "document/revision pair is incomplete"
            )
        }
    }

    private func validateIdentity(
        current: RuntimeVMLifecycleDocument,
        proposed: RuntimeVMLifecycleDocument
    ) throws {
        guard current.bootID == proposed.bootID else {
            throw RuntimeVMLifecycleTransitionError.runIDMismatch(
                expected: current.bootID ?? "missing",
                actual: proposed.bootID ?? "missing"
            )
        }
        guard current.operationID == proposed.operationID else {
            throw RuntimeVMLifecycleTransitionError.operationIDMismatch(
                expected: current.operationID ?? "missing",
                actual: proposed.operationID ?? "missing"
            )
        }
        guard current.operation == proposed.operation else {
            throw RuntimeVMLifecycleTransitionError.operationMismatch(
                expected: current.operation?.rawValue ?? "missing",
                actual: proposed.operation?.rawValue ?? "missing"
            )
        }
        guard current.startedAt == proposed.startedAt else {
            throw RuntimeVMLifecycleTransitionError.startedAtMismatch(
                expected: current.startedAt,
                actual: proposed.startedAt
            )
        }
    }

    private func validateDocument(_ document: RuntimeVMLifecycleDocument) throws {
        guard document.schemaVersion == 1 else {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "schemaVersion",
                value: String(document.schemaVersion)
            )
        }
        guard !document.startedAt.isEmpty else {
            throw RuntimeVMLifecycleTransitionError.invalidField(field: "startedAt", value: document.startedAt)
        }
        guard !document.updatedAt.isEmpty else {
            throw RuntimeVMLifecycleTransitionError.invalidField(field: "updatedAt", value: document.updatedAt)
        }
        guard let bootID = document.bootID, !bootID.isEmpty else {
            throw RuntimeVMLifecycleTransitionError.invalidField(field: "bootID", value: "missing")
        }
        guard let operationID = document.operationID, !operationID.isEmpty else {
            throw RuntimeVMLifecycleTransitionError.invalidField(field: "operationID", value: "missing")
        }
        guard let operation = document.operation, isKnown(operation) else {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "operation",
                value: document.operation?.rawValue ?? "missing"
            )
        }
        if case .unknown = document.state {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "state",
                value: document.state.rawValue
            )
        }
        if document.state == .failed {
            guard let reason = document.terminalReason, isKnown(reason) else {
                throw RuntimeVMLifecycleTransitionError.invalidField(
                    field: "terminalReason",
                    value: document.terminalReason?.rawValue ?? "missing"
                )
            }
        } else if let reason = document.terminalReason {
            throw RuntimeVMLifecycleTransitionError.invalidField(
                field: "terminalReason",
                value: reason.rawValue
            )
        }
        if let deadlineAt = document.deadlineAt, deadlineAt.isEmpty {
            throw RuntimeVMLifecycleTransitionError.invalidField(field: "deadlineAt", value: deadlineAt)
        }
    }

    private func isAllowedTransition(
        from: RuntimeVMLifecycleState,
        to: RuntimeVMLifecycleState
    ) -> Bool {
        if from == to { return true }
        switch from {
        case .starting:
            return [.bootstrapping, .stopping, .stopped, .failed].contains(to)
        case .bootstrapping:
            return [.running, .stopping, .stopped, .failed].contains(to)
        case .running:
            return [.stopping, .stopped, .failed].contains(to)
        case .stopping:
            return [.stopped, .failed].contains(to)
        case .stopped, .failed, .unknown:
            return false
        }
    }

    private func isKnown(_ operation: RuntimeOperation) -> Bool {
        if case .unknown = operation { return false }
        return true
    }

    private func isKnown(_ reason: RuntimeVMLifecycleTerminalReason) -> Bool {
        if case .unknown = reason { return false }
        return true
    }
}
