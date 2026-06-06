import Foundation

public enum VMRuntimeConfigReadError: Error, Equatable {
    case missingConfig(String)
}
