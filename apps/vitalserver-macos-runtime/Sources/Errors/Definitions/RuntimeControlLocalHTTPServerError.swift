import Foundation

public enum RuntimeControlLocalHTTPServerError: Error, Equatable {
    case invalidPort(UInt16)
    case listenerUnavailable
}
