import Foundation

public enum VMRuntimeBootFileValidationError: Error, Equatable {
    case missingFile(String)
}
