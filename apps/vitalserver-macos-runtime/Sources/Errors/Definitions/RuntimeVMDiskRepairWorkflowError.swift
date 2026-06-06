import Foundation

public enum RuntimeVMDiskRepairWorkflowError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}
