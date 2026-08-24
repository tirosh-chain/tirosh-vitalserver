import Application
import Contracts
import Foundation

public enum PlatformAgentUpdateBootstrapVerifiedSelectionWriteError:
    Error,
    Equatable
{
    case invalidSelection(reason: String)
    case destinationIdentityMismatch(expected: String, actual: String)
    case destinationIsDirectory(path: String)
    case destinationInspectionFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case writePermissionDenied(path: String, reason: String)
}

public struct PlatformAgentUpdateBootstrapVerifiedSelectionWriteOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let validate: (PlatformAgentUpdateBootstrapVerifiedSelection) throws
        -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        validate: @escaping (PlatformAgentUpdateBootstrapVerifiedSelection)
            throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.validate = validate
    }
}

public struct PlatformAgentUpdateBootstrapVerifiedSelectionWriter:
    PlatformAgentUpdateBootstrapVerifiedSelectionWriting
{
    public let operations:
        PlatformAgentUpdateBootstrapVerifiedSelectionWriteOperations

    public init(
        operations:
            PlatformAgentUpdateBootstrapVerifiedSelectionWriteOperations
    ) {
        self.operations = operations
    }

    public func write(
        _ selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        to destination: URL
    ) throws {
        do {
            try operations.validate(selection)
        } catch {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .invalidSelection(reason: String(describing: error))
        }
        let expectedName =
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.fileName
        guard destination.lastPathComponent == expectedName else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .destinationIdentityMismatch(
                    expected: expectedName,
                    actual: destination.lastPathComponent
                )
        }
        try requireWritableDestination(destination)

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(selection)
        } catch {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .encodeFailed(reason: String(describing: error))
        }

        do {
            try operations.createDirectory(
                destination.deletingLastPathComponent(),
                true
            )
            try operations.writeData(data, destination, [.atomic])
        } catch {
            if POSIXFileAccessFailure.isPermissionDenied(error) {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                    .writePermissionDenied(
                        path: destination.path,
                        reason: String(describing: error)
                    )
            }
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .writeFailed(
                    path: destination.path,
                    reason: String(describing: error)
                )
        }
    }

    private func requireWritableDestination(_ destination: URL) throws {
        switch operations.pathState(destination) {
        case .missing, .file:
            return
        case .directory:
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .destinationIsDirectory(path: destination.path)
        case .other(let value):
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unexpected path state: \(value)"
                )
        case .inspectFailed(let reason):
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: reason
                )
        case .unknown(let value):
            throw PlatformAgentUpdateBootstrapVerifiedSelectionWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unknown path state: \(value)"
                )
        }
    }
}

public struct PlatformAgentUpdateBootstrapVerifiedSelectionReader:
    PlatformAgentUpdateBootstrapVerifiedSelectionReading
{
    public let pathState: (URL) -> RuntimePathState
    public let readData: (URL) throws -> Data

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        readData: @escaping (URL) throws -> Data
    ) {
        self.pathState = pathState
        self.readData = readData
    }

    public func read(
        at url: URL
    ) -> PlatformAgentUpdateBootstrapVerifiedSelectionReadResult {
        switch pathState(url) {
        case .missing:
            return .missing(path: url.path)
        case .file:
            break
        case .directory:
            return .unexpectedPathState(path: url.path, state: "directory")
        case .other(let value):
            return .unexpectedPathState(path: url.path, state: value)
        case .inspectFailed(let reason):
            return .inspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            return .unexpectedPathState(path: url.path, state: value)
        }

        let data: Data
        do {
            data = try readData(url)
        } catch {
            if POSIXFileAccessFailure.isPermissionDenied(error) {
                return .permissionDenied(
                    path: url.path,
                    reason: String(describing: error)
                )
            }
            return .readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
        do {
            return .loaded(
                try JSONDecoder().decode(
                    PlatformAgentUpdateBootstrapVerifiedSelection.self,
                    from: data
                )
            )
        } catch {
            return .decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }
}
