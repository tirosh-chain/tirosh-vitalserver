import Contracts
import Foundation

public enum UpdateBootstrapHandoffInvocationWriteError: Error, Equatable {
    case destinationAlreadyExists(path: String, state: String)
    case destinationInspectionFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
}

public struct UpdateBootstrapHandoffInvocationWriteOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
    }
}

public struct UpdateBootstrapHandoffInvocationWriter {
    public static let relativePath = "handoff/invocation.json"

    public let operations: UpdateBootstrapHandoffInvocationWriteOperations

    public init(operations: UpdateBootstrapHandoffInvocationWriteOperations) {
        self.operations = operations
    }

    public func write(
        _ invocation: UpdateBootstrapHandoffInvocation,
        stagedBundleRoot: URL
    ) throws -> WrittenUpdateBootstrapHandoffInvocation {
        let destination = stagedBundleRoot.appendingPathComponent(
            Self.relativePath
        )
        try requireMissing(destination)

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(invocation)
        } catch {
            throw UpdateBootstrapHandoffInvocationWriteError.encodeFailed(
                reason: String(describing: error)
            )
        }

        do {
            try operations.createDirectory(
                destination.deletingLastPathComponent(),
                true
            )
            try operations.writeData(data, destination, [.atomic])
        } catch {
            throw UpdateBootstrapHandoffInvocationWriteError.writeFailed(
                path: destination.path,
                reason: String(describing: error)
            )
        }
        return WrittenUpdateBootstrapHandoffInvocation(url: destination)
    }

    private func requireMissing(_ destination: URL) throws {
        switch operations.pathState(destination) {
        case .missing:
            return
        case .file:
            throw existing(destination, state: "file")
        case .directory:
            throw existing(destination, state: "directory")
        case .other(let value):
            throw existing(destination, state: value)
        case .inspectFailed(let reason):
            throw UpdateBootstrapHandoffInvocationWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: reason
                )
        case .unknown(let value):
            throw existing(destination, state: value)
        }
    }

    private func existing(
        _ destination: URL,
        state: String
    ) -> UpdateBootstrapHandoffInvocationWriteError {
        .destinationAlreadyExists(path: destination.path, state: state)
    }
}
