import Contracts

public struct RuntimeWorkflowOperationTransitionState: Equatable, Sendable {
    public let operationID: String
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let currentStep: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let revision: Int

    public init(
        operationID: String,
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        revision: Int
    ) {
        self.operationID = operationID
        self.operation = operation
        self.phase = phase
        self.currentStep = currentStep
        self.stepStatus = stepStatus
        self.revision = revision
    }
}

public enum RuntimeWorkflowOperationTransitionEvent: Equatable, Sendable {
    case started(operationID: String, operation: RuntimeOperation, message: String)
    case updated(
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String]
    )
    case progressed(RuntimeStepExecutionEvent)
    case completed(message: String)
    case failed(message: String, reasonCodes: [String])
}

public struct RuntimeWorkflowOperationTransitionDecision: Equatable, Sendable {
    public let operationID: String
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let currentStep: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let completed: Bool
    public let requiresPersistence: Bool
    public let expectedRevision: Int?

    public init(
        operationID: String,
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        completed: Bool,
        requiresPersistence: Bool = true,
        expectedRevision: Int?
    ) {
        self.operationID = operationID
        self.operation = operation
        self.phase = phase
        self.currentStep = currentStep
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.completed = completed
        self.requiresPersistence = requiresPersistence
        self.expectedRevision = expectedRevision
    }
}

public enum RuntimeWorkflowOperationTransitionError: Error, Equatable, CustomStringConvertible {
    case invalidOperationID
    case invalidRevision(Int)
    case incompleteStepState
    case missingState
    case operationAlreadyStarted(String)
    case operationMismatch(expected: String, actual: String)
    case terminalState(String)
    case invalidProgress(stepStatus: String, phase: String)
    case unknownValue(field: String, value: String)

    public var description: String {
        switch self {
        case .invalidOperationID:
            return "workflow operation ID is empty"
        case .invalidRevision(let revision):
            return "workflow operation revision is invalid: \(revision)"
        case .incompleteStepState:
            return "workflow operation step and step status must both be present or absent"
        case .missingState:
            return "workflow operation state is missing"
        case .operationAlreadyStarted(let operationID):
            return "workflow operation is already started: \(operationID)"
        case .operationMismatch(let expected, let actual):
            return "workflow operation mismatch expected=\(expected) actual=\(actual)"
        case .terminalState(let phase):
            return "workflow operation is already terminal phase=\(phase)"
        case .invalidProgress(let stepStatus, let phase):
            return "workflow operation progress is invalid stepStatus=\(stepStatus) phase=\(phase)"
        case .unknownValue(let field, let value):
            return "workflow operation contains unknown value field=\(field) value=\(value)"
        }
    }
}

public struct RuntimeWorkflowOperationStateMachine {
    public init() {}

    public func transition(
        current: RuntimeWorkflowOperationTransitionState?,
        event: RuntimeWorkflowOperationTransitionEvent
    ) throws -> RuntimeWorkflowOperationTransitionDecision {
        if let current {
            try validate(current)
        }

        switch event {
        case .started(let operationID, let operation, let message):
            guard current == nil else {
                throw RuntimeWorkflowOperationTransitionError.operationAlreadyStarted(current!.operationID)
            }
            guard !operationID.isEmpty else {
                throw RuntimeWorkflowOperationTransitionError.invalidOperationID
            }
            try requireKnown(operation, field: "operation")
            return RuntimeWorkflowOperationTransitionDecision(
                operationID: operationID,
                operation: operation,
                phase: .preparing,
                currentStep: nil,
                stepStatus: nil,
                message: message,
                reasonCodes: [],
                completed: false,
                expectedRevision: nil
            )

        case .updated(let phase, let currentStep, let stepStatus, let message, let reasonCodes):
            let current = try requireActive(current)
            try requireKnown(phase, field: "phase")
            if let currentStep {
                try requireKnown(currentStep, field: "step")
            }
            if let stepStatus {
                try requireKnown(stepStatus, field: "stepStatus")
            }
            guard (currentStep == nil) == (stepStatus == nil) else {
                throw RuntimeWorkflowOperationTransitionError.incompleteStepState
            }
            guard phase != .completed && phase != .failed && phase != .cancelled else {
                throw RuntimeWorkflowOperationTransitionError.invalidProgress(
                    stepStatus: stepStatus?.rawValue ?? "none",
                    phase: phase.rawValue
                )
            }
            return decision(
                current: current,
                phase: phase,
                step: currentStep,
                stepStatus: stepStatus,
                message: message,
                reasonCodes: reasonCodes,
                completed: false
            )

        case .progressed(let progress):
            let current = try requireActive(current)
            guard current.operation == progress.operation else {
                throw RuntimeWorkflowOperationTransitionError.operationMismatch(
                    expected: current.operation.rawValue,
                    actual: progress.operation.rawValue
                )
            }
            try requireKnown(progress.operation, field: "operation")
            try requireKnown(progress.step, field: "step")
            try requireKnown(progress.stepStatus, field: "stepStatus")
            try requireKnown(progress.phase, field: "phase")
            guard progress.stepStatus != .failed || progress.phase == .failed else {
                throw RuntimeWorkflowOperationTransitionError.invalidProgress(
                    stepStatus: progress.stepStatus.rawValue,
                    phase: progress.phase.rawValue
                )
            }
            guard progress.phase != .completed && progress.phase != .cancelled else {
                throw RuntimeWorkflowOperationTransitionError.invalidProgress(
                    stepStatus: progress.stepStatus.rawValue,
                    phase: progress.phase.rawValue
                )
            }
            return decision(
                current: current,
                phase: progress.phase,
                step: progress.step,
                stepStatus: progress.stepStatus,
                message: progress.message,
                reasonCodes: [],
                completed: progress.phase == .failed
            )

        case .completed(let message):
            let current = try requireActive(current)
            return decision(
                current: current,
                phase: .completed,
                step: nil,
                stepStatus: nil,
                message: message,
                reasonCodes: [],
                completed: true
            )

        case .failed(let message, let reasonCodes):
            guard let current else {
                throw RuntimeWorkflowOperationTransitionError.missingState
            }
            if current.phase == .failed {
                return decision(
                    current: current,
                    phase: current.phase,
                    step: current.currentStep,
                    stepStatus: current.stepStatus,
                    message: message,
                    reasonCodes: reasonCodes,
                    completed: true,
                    requiresPersistence: false
                )
            }
            _ = try requireActive(current)
            return decision(
                current: current,
                phase: .failed,
                step: current.currentStep,
                stepStatus: current.stepStatus,
                message: message,
                reasonCodes: reasonCodes,
                completed: true
            )
        }
    }

    private func validate(_ state: RuntimeWorkflowOperationTransitionState) throws {
        guard !state.operationID.isEmpty else {
            throw RuntimeWorkflowOperationTransitionError.invalidOperationID
        }
        guard state.revision > 0 else {
            throw RuntimeWorkflowOperationTransitionError.invalidRevision(state.revision)
        }
        guard (state.currentStep == nil) == (state.stepStatus == nil) else {
            throw RuntimeWorkflowOperationTransitionError.incompleteStepState
        }
        try requireKnown(state.operation, field: "operation")
        try requireKnown(state.phase, field: "phase")
        if let currentStep = state.currentStep {
            try requireKnown(currentStep, field: "step")
        }
        if let stepStatus = state.stepStatus {
            try requireKnown(stepStatus, field: "stepStatus")
        }
    }

    private func requireActive(
        _ state: RuntimeWorkflowOperationTransitionState?
    ) throws -> RuntimeWorkflowOperationTransitionState {
        guard let state else {
            throw RuntimeWorkflowOperationTransitionError.missingState
        }
        switch state.phase {
        case .completed, .failed, .cancelled:
            throw RuntimeWorkflowOperationTransitionError.terminalState(state.phase.rawValue)
        default:
            return state
        }
    }

    private func decision(
        current: RuntimeWorkflowOperationTransitionState,
        phase: RuntimeProgressPhase,
        step: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        completed: Bool,
        requiresPersistence: Bool = true
    ) -> RuntimeWorkflowOperationTransitionDecision {
        RuntimeWorkflowOperationTransitionDecision(
            operationID: current.operationID,
            operation: current.operation,
            phase: phase,
            currentStep: step,
            stepStatus: stepStatus,
            message: message,
            reasonCodes: reasonCodes,
            completed: completed,
            requiresPersistence: requiresPersistence,
            expectedRevision: current.revision
        )
    }

    private func requireKnown(_ value: RuntimeOperation, field: String) throws {
        if case .unknown(let rawValue) = value {
            throw RuntimeWorkflowOperationTransitionError.unknownValue(field: field, value: rawValue)
        }
    }

    private func requireKnown(_ value: RuntimeProgressPhase, field: String) throws {
        if case .unknown(let rawValue) = value {
            throw RuntimeWorkflowOperationTransitionError.unknownValue(field: field, value: rawValue)
        }
    }

    private func requireKnown(_ value: RuntimeWorkflowStep, field: String) throws {
        if case .unknown(let rawValue) = value {
            throw RuntimeWorkflowOperationTransitionError.unknownValue(field: field, value: rawValue)
        }
    }

    private func requireKnown(_ value: RuntimeProgressStepStatus, field: String) throws {
        if case .unknown(let rawValue) = value {
            throw RuntimeWorkflowOperationTransitionError.unknownValue(field: field, value: rawValue)
        }
    }
}
