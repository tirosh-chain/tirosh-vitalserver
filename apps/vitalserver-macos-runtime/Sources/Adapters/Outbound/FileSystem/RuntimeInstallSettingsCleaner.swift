import Foundation
import Contracts
import Errors

public struct RuntimeInstallSettingsCleanupContext {
    public let settingsFile: URL

    public init(settingsFile: URL) {
        self.settingsFile = settingsFile
    }
}

public struct RuntimeInstallSettingsCleanupOperations {
    public let pathState: (URL) -> RuntimePathState
    public let removeItem: (URL) throws -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        removeItem: @escaping (URL) throws -> Void
    ) {
        self.pathState = pathState
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
        let state = operations.pathState(context.settingsFile)
        switch state {
        case .file:
            try operations.removeItem(context.settingsFile)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeInstallSettingsCleanupError.pathInspectionFailed(
                path: context.settingsFile.path,
                reason: reason
            )
        case .directory, .other, .unknown:
            throw RuntimeInstallSettingsCleanupError.unexpectedPathState(
                path: context.settingsFile.path,
                state: state.rawValue
            )
        }
    }
}
