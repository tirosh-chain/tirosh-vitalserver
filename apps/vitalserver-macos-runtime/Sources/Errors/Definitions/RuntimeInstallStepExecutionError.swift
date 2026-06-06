import Foundation
import Contracts

public struct RuntimeInstallStepExecutionError: Error, Equatable, CustomStringConvertible {
    public let step: RuntimeWorkflowStep

    public init(step: RuntimeWorkflowStep) {
        self.step = step
    }

    public var description: String {
        "unsupported command: install step \(step.rawValue)"
    }
}
