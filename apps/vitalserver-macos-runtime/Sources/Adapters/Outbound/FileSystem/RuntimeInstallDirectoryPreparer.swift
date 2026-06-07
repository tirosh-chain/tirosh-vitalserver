import Foundation
import Contracts
import Errors

public struct RuntimeInstallDirectoryPreparationContext<Settings> {
    public var fixedDirectories: [URL]
    public var staleGuestRunDocuments: [URL]
    public var vitalFilesDirectory: (Settings) -> URL

    public init(
        fixedDirectories: [URL],
        staleGuestRunDocuments: [URL],
        vitalFilesDirectory: @escaping (Settings) -> URL
    ) {
        self.fixedDirectories = fixedDirectories
        self.staleGuestRunDocuments = staleGuestRunDocuments
        self.vitalFilesDirectory = vitalFilesDirectory
    }
}

public struct RuntimeInstallDirectoryPreparationOperations {
    public var createDirectory: (URL, Bool) throws -> Void
    public var pathState: (URL) -> RuntimePathState
    public var removeItem: (URL) throws -> Void

    public init(
        createDirectory: @escaping (URL, Bool) throws -> Void,
        pathState: @escaping (URL) -> RuntimePathState,
        removeItem: @escaping (URL) throws -> Void
    ) {
        self.createDirectory = createDirectory
        self.pathState = pathState
        self.removeItem = removeItem
    }
}

public struct RuntimeInstallDirectoryPreparer<Settings> {
    public var context: RuntimeInstallDirectoryPreparationContext<Settings>
    public var operations: RuntimeInstallDirectoryPreparationOperations

    public init(
        context: RuntimeInstallDirectoryPreparationContext<Settings>,
        operations: RuntimeInstallDirectoryPreparationOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func prepare(settings: Settings) throws {
        let directories = [context.vitalFilesDirectory(settings)] + context.fixedDirectories
        for directory in directories {
            try operations.createDirectory(directory, true)
        }
        try removeStaleGuestRunDocuments()
    }

    private func removeStaleGuestRunDocuments() throws {
        for document in context.staleGuestRunDocuments {
            let state = operations.pathState(document)
            switch state {
            case .file:
                try operations.removeItem(document)
            case .missing:
                continue
            case .inspectFailed(let reason):
                throw RuntimeInstallDirectoryPreparationError.pathInspectionFailed(
                    path: document.path,
                    reason: reason
                )
            case .directory, .other, .unknown:
                throw RuntimeInstallDirectoryPreparationError.unexpectedPathState(
                    path: document.path,
                    state: state.rawValue
                )
            }
        }
    }
}
