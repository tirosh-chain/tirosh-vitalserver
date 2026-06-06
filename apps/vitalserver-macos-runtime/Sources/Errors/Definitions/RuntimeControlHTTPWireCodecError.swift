import Foundation

public enum RuntimeControlHTTPWireCodecError: Error, Equatable {
    case invalidRequest
    case unsupportedMethod(String)
    case invalidContentLength(String)
}
