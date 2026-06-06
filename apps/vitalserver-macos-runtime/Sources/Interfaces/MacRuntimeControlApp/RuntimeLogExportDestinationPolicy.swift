import Foundation

public struct RuntimeLogExportDirectoryState: Equatable {
    public let path: String
    public let isWritable: Bool

    public init(path: String, isWritable: Bool) {
        self.path = path
        self.isWritable = isWritable
    }
}

public struct RuntimeLogExportDestinationFacts: Equatable {
    public let isFileURL: Bool
    public let path: String
    public let pathExtension: String
    public let isExistingDirectoryDestination: Bool
    public let nearestExistingDirectory: RuntimeLogExportDirectoryState?

    public init(
        isFileURL: Bool,
        path: String,
        pathExtension: String,
        isExistingDirectoryDestination: Bool,
        nearestExistingDirectory: RuntimeLogExportDirectoryState?
    ) {
        self.isFileURL = isFileURL
        self.path = path
        self.pathExtension = pathExtension
        self.isExistingDirectoryDestination = isExistingDirectoryDestination
        self.nearestExistingDirectory = nearestExistingDirectory
    }
}

public enum RuntimeLogExportDestinationValidationResult: Equatable {
    case valid
    case invalidDestination
    case existingDirectoryDestination
    case protectedDirectory
    case parentDirectoryNotWritable
}

public struct RuntimeLogExportDestinationPolicy {
    public init() {}

    public func validationResult(for facts: RuntimeLogExportDestinationFacts) -> RuntimeLogExportDestinationValidationResult {
        guard facts.isFileURL, !facts.path.isEmpty else {
            return .invalidDestination
        }

        let standardized = URL(fileURLWithPath: facts.path).standardizedFileURL
        if facts.isExistingDirectoryDestination {
            return .existingDirectoryDestination
        }

        if facts.pathExtension.lowercased() != "zip" {
            return .invalidDestination
        }

        let parent = standardized.deletingLastPathComponent()
        guard canNavigateDirectoryPath(parent.path) else {
            return .protectedDirectory
        }

        guard let writableDirectory = facts.nearestExistingDirectory else {
            return .invalidDestination
        }

        guard writableDirectory.isWritable else {
            return .parentDirectoryNotWritable
        }

        return .valid
    }

    public func canNavigateDirectoryPath(_ path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return !isICloudDrivePath(standardizedPath)
            && !isProtectedUserPath(standardizedPath)
            && !isSystemManagedPath(standardizedPath)
    }

    private func isICloudDrivePath(_ path: String) -> Bool {
        path.contains("/Library/Mobile Documents/")
            || path.hasSuffix("/Library/Mobile Documents")
    }

    private func isProtectedUserPath(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 4,
              components[0] == "/",
              components[1] == "Users" else {
            return false
        }
        return ["Desktop", "Documents"].contains(components[3])
    }

    private func isSystemManagedPath(_ path: String) -> Bool {
        path == "/"
            || path == "/Applications"
            || path.hasPrefix("/Applications/")
            || path == "/Library"
            || path.hasPrefix("/Library/")
            || path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || (path.hasPrefix("/usr/") && !path.hasPrefix("/usr/local/"))
    }
}
