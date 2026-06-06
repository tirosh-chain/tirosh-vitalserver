import Foundation

public enum CompositeRuntimeEventRepositoryError: Error, Equatable, CustomStringConvertible {
    case secondaryAppendFailed(eventID: String, error: String)

    public var description: String {
        switch self {
        case .secondaryAppendFailed(let eventID, let error):
            return "runtime event sqlite append failed eventID=\(eventID) error=\(error)"
        }
    }
}
