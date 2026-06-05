import Foundation

public struct RuntimeInstallSettingsCleanupContext {
    public let settingsFile: URL

    public init(settingsFile: URL) {
        self.settingsFile = settingsFile
    }
}

public struct RuntimeInstallSettingsCleanupOperations {
    public let fileExists: (URL) -> Bool
    public let removeItem: (URL) throws -> Void

    public init(
        fileExists: @escaping (URL) -> Bool,
        removeItem: @escaping (URL) throws -> Void
    ) {
        self.fileExists = fileExists
        self.removeItem = removeItem
    }
}

public struct RuntimeInstallSettingsCleaner {
    public let context: RuntimeInstallSettingsCleanupContext
    public let operations: RuntimeInstallSettingsCleanupOperations

    public init(
        context: RuntimeInstallSettingsCleanupContext,
        operations: RuntimeInstallSettingsCleanupOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func cleanup() throws {
        if operations.fileExists(context.settingsFile) {
            try operations.removeItem(context.settingsFile)
        }
    }
}
