import Contracts
import Foundation

public enum ImmutableUpdateBootstrapStagingError: Error, Equatable {
    case invalidIdentifier(field: String, value: String)
    case sourceIsNotDirectory(path: String, state: String)
    case sourceInspectionFailed(path: String, reason: String)
    case destinationAlreadyExists(path: String, state: String)
    case destinationInspectionFailed(path: String, reason: String)
    case temporaryDestinationAlreadyExists(path: String, state: String)
    case temporaryDestinationInspectionFailed(path: String, reason: String)
    case stagingFailed(reason: String)
    case stagingFailedAndCleanupFailed(stagingReason: String, cleanupReason: String)
}

public struct ImmutableUpdateBootstrapStagingOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let copyItem: (URL, URL) throws -> Void
    public let moveItem: (URL, URL) throws -> Void
    public let removeItem: (URL) throws -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        copyItem: @escaping (URL, URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        removeItem: @escaping (URL) throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.copyItem = copyItem
        self.moveItem = moveItem
        self.removeItem = removeItem
    }
}

public struct ImmutableUpdateBootstrapStager {
    public let stagingRoot: URL
    public let operations: ImmutableUpdateBootstrapStagingOperations

    public init(
        stagingRoot: URL,
        operations: ImmutableUpdateBootstrapStagingOperations
    ) {
        self.stagingRoot = stagingRoot
        self.operations = operations
    }

    public func stage(
        _ input: UpdateBootstrapStagingInput
    ) throws -> StagedUpdateBootstrapBundle {
        try validatePathComponent(input.updateId, field: "updateId")
        try validatePathComponent(input.stagingAttemptId, field: "stagingAttemptId")
        try requireSourceDirectory(input.sourceBundle)

        let destination = stagingRoot.appendingPathComponent(
            input.updateId,
            isDirectory: true
        )
        let temporaryDestination = stagingRoot.appendingPathComponent(
            ".\(input.updateId).staging-\(input.stagingAttemptId)",
            isDirectory: true
        )
        try requireMissingDestination(destination)
        try requireMissingTemporaryDestination(temporaryDestination)
        try operations.createDirectory(stagingRoot, true)

        do {
            try operations.copyItem(input.sourceBundle, temporaryDestination)
            try operations.moveItem(temporaryDestination, destination)
        } catch {
            let stagingReason = String(describing: error)
            switch operations.pathState(temporaryDestination) {
            case .missing:
                throw ImmutableUpdateBootstrapStagingError.stagingFailed(
                    reason: stagingReason
                )
            case .file, .directory, .other:
                do {
                    try operations.removeItem(temporaryDestination)
                } catch {
                    throw ImmutableUpdateBootstrapStagingError
                        .stagingFailedAndCleanupFailed(
                            stagingReason: stagingReason,
                            cleanupReason: String(describing: error)
                        )
                }
                throw ImmutableUpdateBootstrapStagingError.stagingFailed(
                    reason: stagingReason
                )
            case .inspectFailed(let reason):
                throw ImmutableUpdateBootstrapStagingError
                    .stagingFailedAndCleanupFailed(
                        stagingReason: stagingReason,
                        cleanupReason: "temporary destination inspection failed: \(reason)"
                    )
            case .unknown(let value):
                throw ImmutableUpdateBootstrapStagingError
                    .stagingFailedAndCleanupFailed(
                        stagingReason: stagingReason,
                        cleanupReason: "temporary destination state is unknown: \(value)"
                    )
            }
        }
        return StagedUpdateBootstrapBundle(root: destination)
    }

    private func validatePathComponent(_ value: String, field: String) throws {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        guard !value.isEmpty,
              value != ".",
              value != "..",
              value.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw ImmutableUpdateBootstrapStagingError.invalidIdentifier(
                field: field,
                value: value
            )
        }
    }

    private func requireSourceDirectory(_ source: URL) throws {
        switch operations.pathState(source) {
        case .directory:
            return
        case .missing:
            throw ImmutableUpdateBootstrapStagingError.sourceIsNotDirectory(
                path: source.path,
                state: "missing"
            )
        case .file:
            throw ImmutableUpdateBootstrapStagingError.sourceIsNotDirectory(
                path: source.path,
                state: "file"
            )
        case .other(let value):
            throw ImmutableUpdateBootstrapStagingError.sourceIsNotDirectory(
                path: source.path,
                state: value
            )
        case .inspectFailed(let reason):
            throw ImmutableUpdateBootstrapStagingError.sourceInspectionFailed(
                path: source.path,
                reason: reason
            )
        case .unknown(let value):
            throw ImmutableUpdateBootstrapStagingError.sourceIsNotDirectory(
                path: source.path,
                state: value
            )
        }
    }

    private func requireMissingDestination(_ destination: URL) throws {
        switch operations.pathState(destination) {
        case .missing:
            return
        case .file:
            throw existingDestination(destination, state: "file")
        case .directory:
            throw existingDestination(destination, state: "directory")
        case .other(let value):
            throw existingDestination(destination, state: value)
        case .inspectFailed(let reason):
            throw ImmutableUpdateBootstrapStagingError.destinationInspectionFailed(
                path: destination.path,
                reason: reason
            )
        case .unknown(let value):
            throw existingDestination(destination, state: value)
        }
    }

    private func existingDestination(
        _ destination: URL,
        state: String
    ) -> ImmutableUpdateBootstrapStagingError {
        .destinationAlreadyExists(path: destination.path, state: state)
    }

    private func requireMissingTemporaryDestination(_ destination: URL) throws {
        switch operations.pathState(destination) {
        case .missing:
            return
        case .file:
            throw existingTemporaryDestination(destination, state: "file")
        case .directory:
            throw existingTemporaryDestination(destination, state: "directory")
        case .other(let value):
            throw existingTemporaryDestination(destination, state: value)
        case .inspectFailed(let reason):
            throw ImmutableUpdateBootstrapStagingError
                .temporaryDestinationInspectionFailed(
                    path: destination.path,
                    reason: reason
                )
        case .unknown(let value):
            throw existingTemporaryDestination(destination, state: value)
        }
    }

    private func existingTemporaryDestination(
        _ destination: URL,
        state: String
    ) -> ImmutableUpdateBootstrapStagingError {
        .temporaryDestinationAlreadyExists(path: destination.path, state: state)
    }
}
