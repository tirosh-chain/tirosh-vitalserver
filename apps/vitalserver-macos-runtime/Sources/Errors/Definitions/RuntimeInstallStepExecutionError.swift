import Foundation
import Contracts

public struct RuntimeInstallStepExecutionError: Error, Equatable, CustomStringConvertible {
    public let step: RuntimeWorkflowStep?
    public let message: String

    public init(step: RuntimeWorkflowStep) {
        self.step = step
        self.message = "unsupported command: install step \(step.rawValue)"
    }

    public init(_ message: String) {
        self.step = nil
        self.message = message
    }

    public var description: String {
        message
    }
}
