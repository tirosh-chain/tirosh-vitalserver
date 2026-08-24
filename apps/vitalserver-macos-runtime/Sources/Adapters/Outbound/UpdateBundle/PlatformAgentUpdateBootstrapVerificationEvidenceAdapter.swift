import Application
import Contracts
import Foundation

public enum PlatformAgentUpdateBootstrapVerificationEvidenceWriteError:
    Error,
    Equatable
{
    case invalidEvidence(reason: String)
    case destinationIdentityMismatch(expected: String, actual: String)
    case destinationIsDirectory(path: String)
    case destinationInspectionFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case writePermissionDenied(path: String, reason: String)
}

public struct PlatformAgentUpdateBootstrapVerificationEvidenceWriteOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let validate: (PlatformAgentUpdateBootstrapVerificationEvidence) throws
        -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        validate: @escaping (PlatformAgentUpdateBootstrapVerificationEvidence)
            throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.validate = validate
    }
}

public struct PlatformAgentUpdateBootstrapVerificationEvidenceWriter:
    PlatformAgentUpdateBootstrapVerificationEvidenceWriting
{
    public let operations:
        PlatformAgentUpdateBootstrapVerificationEvidenceWriteOperations

    public init(
        operations:
            PlatformAgentUpdateBootstrapVerificationEvidenceWriteOperations
    ) {
        self.operations = operations
    }

    public func write(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence,
        to destination: URL
    ) throws {
        do {
            try operations.validate(evidence)
        } catch {
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                .invalidEvidence(reason: String(describing: error))
        }
        let expectedName =
            PlatformAgentUpdateBootstrapVerificationContract.fileName(
                verificationInvocationId: evidence.verificationInvocationId
            )
        guard destination.lastPathComponent == expectedName else {
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
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
            data = try encoder.encode(evidence)
        } catch {
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
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
                throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                    .writePermissionDenied(
                        path: destination.path,
                        reason: String(describing: error)
                    )
            }
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
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
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                .destinationIsDirectory(path: destination.path)
        case .other(let value):
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unexpected path state: \(value)"
                )
        case .inspectFailed(let reason):
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: reason
                )
        case .unknown(let value):
            throw PlatformAgentUpdateBootstrapVerificationEvidenceWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unknown path state: \(value)"
                )
        }
    }
}

public struct PlatformAgentUpdateBootstrapVerificationEvidenceReader:
    PlatformAgentUpdateBootstrapVerificationEvidenceReading
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
    ) -> PlatformAgentUpdateBootstrapVerificationEvidenceReadResult {
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
                    PlatformAgentUpdateBootstrapVerificationEvidence.self,
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
