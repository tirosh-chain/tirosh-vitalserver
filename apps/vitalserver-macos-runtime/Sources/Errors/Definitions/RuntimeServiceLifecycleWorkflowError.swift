import Foundation

public enum RuntimeServiceLifecycleWorkflowError: Error, Equatable {
    case operationFailed(String)
}
