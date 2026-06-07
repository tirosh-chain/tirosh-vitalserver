import Foundation

public enum RuntimeOperationLeaseRepositoryError: Error, Equatable, CustomStringConvertible {
    case existingOperation(operationId: String, operation: String)
    case readFailed(String)
    case createFailed(String)
    case operationIdMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .existingOperation(let operationId, let operation):
            return "runtime operation lease already exists operationId=\(operationId) operation=\(operation)"
        case .readFailed(let reason):
            return "runtime operation lease read failed: \(reason)"
        case .createFailed(let path):
            return "runtime operation lease create failed path=\(path)"
        case .operationIdMismatch(let expected, let actual):
            return "runtime operation lease operationId mismatch expected=\(expected) actual=\(actual)"
        }
    }
}
