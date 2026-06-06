import Foundation
import Contracts

public struct RuntimeOperationPlanValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let operation: RuntimeOperation
    public let invalidSteps: [RuntimeWorkflowStep]

    public init(operation: RuntimeOperation, invalidSteps: [RuntimeWorkflowStep]) {
        self.operation = operation
        self.invalidSteps = invalidSteps
    }

    public var description: String {
        let stepNames = invalidSteps.map(\.rawValue).joined(separator: ", ")
        return "invalid steps for \(operation.rawValue): \(stepNames)"
    }
}
